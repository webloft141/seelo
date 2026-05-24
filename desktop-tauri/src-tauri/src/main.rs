use serde::{Deserialize, Serialize};
use socketioxide::extract::{Data, SocketRef};
use std::collections::HashMap;
use std::sync::Arc;
use tauri::{Emitter, Manager};
use tokio::sync::RwLock;
use qrcode::{render::svg, QrCode};
use tauri_plugin_autostart::MacosLauncher;
mod ble_advertiser;

#[derive(Clone, Serialize, Deserialize, Default)]
struct MobileInfo {
    name: String,
    width: u32,
    height: u32,
}

fn generate_secret() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let pid = std::process::id() as u128;
    format!("{:032x}", nanos.wrapping_add(pid << 64))
}

#[derive(Clone, Default)]
struct AppState {
    app_handle: Option<tauri::AppHandle>,
    plugin_socket: Option<String>,
    plugin_last_heartbeat_ms: Option<u64>,
    plugin_protocol: Option<String>,
    mobiles: HashMap<String, MobileInfo>,
    design_cache: Option<serde_json::Value>,
    full_export_cache: Option<serde_json::Value>,
    room_secret: Option<String>,
    server_port: u16,
}

#[derive(Clone, Serialize)]
struct MobileListItem {
    id: String,
    name: String,
    width: u32,
    height: u32,
}

fn build_mobile_list(st: &AppState) -> Vec<serde_json::Value> {
    st.mobiles
        .iter()
        .map(|(id, info)| {
            serde_json::json!({
                "socketId": id,
                "deviceName": info.name,
                "screenWidth": info.width,
                "screenHeight": info.height
            })
        })
        .collect()
}

fn mobile_items(st: &AppState) -> Vec<MobileListItem> {
    st.mobiles
        .iter()
        .map(|(id, info)| MobileListItem {
            id: id.clone(),
            name: info.name.clone(),
            width: info.width,
            height: info.height,
        })
        .collect()
}

#[derive(Serialize)]
struct PluginHealth {
    connected: bool,
    stale: bool,
    last_heartbeat_ms: Option<u64>,
    age_ms: Option<u64>,
    protocol: Option<String>,
}

#[derive(Serialize)]
struct PairingQr {
    payload: String,
    svg: String,
}

#[tauri::command]
async fn get_mobiles(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
) -> Result<Vec<MobileListItem>, String> {
    let app_state = state.inner().clone();
    let st = app_state.read().await;
    let mobiles = mobile_items(&st);
    Ok(mobiles)
}

#[tauri::command]
async fn block_mobile(
    socket_id: String,
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    app: tauri::AppHandle,
) -> Result<bool, String> {
    let app_state = state.inner().clone();
    let mut st = app_state.write().await;
    let removed = st.mobiles.remove(&socket_id).is_some();
    if removed {
        if let Some(io) = app.try_state::<socketioxide::SocketIo>() {
            let sockets = io.sockets().unwrap();
            if let Some(ms) = sockets.iter().find(|s| s.id.to_string() == socket_id) {
                let _ = ms.clone().disconnect();
            }
        }
    }
    Ok(removed)
}

#[tauri::command]
fn get_local_ip() -> String {
    let socket = std::net::UdpSocket::bind("0.0.0.0:0");
    if let Ok(sock) = socket {
        if sock.connect("8.8.8.8:80").is_ok() {
            if let Ok(addr) = sock.local_addr() {
                return addr.ip().to_string();
            }
        }
    }
    "127.0.0.1".to_string()
}

#[tauri::command]
async fn get_pairing_qr(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
) -> Result<PairingQr, String> {
    let ip = get_local_ip();
    let (secret, port) = {
        let mut st = state.write().await;
        let secret = st.room_secret.get_or_insert_with(generate_secret).clone();
        let port = st.server_port;
        (secret, port)
    };
    let payload = serde_json::json!({
        "mode": "local",
        "ip": ip,
        "port": port,
        "roomId": "seelo-desktop",
        "roomSecret": secret
    })
    .to_string();

    let code = QrCode::new(payload.as_bytes()).map_err(|e| format!("QR build failed: {e}"))?;
    let svg = code
        .render::<svg::Color>()
        .min_dimensions(220, 220)
        .max_dimensions(220, 220)
        .build();

    Ok(PairingQr { payload, svg })
}

#[tauri::command]
async fn send_to_plugin(
    msg: serde_json::Value,
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
    app: tauri::AppHandle,
) -> Result<bool, String> {
    let st = state.read().await;
    let pid = match &st.plugin_socket {
        Some(pid) => pid.clone(),
        None => return Err("Plugin not connected".into()),
    };
    let io = match app.try_state::<socketioxide::SocketIo>() {
        Some(io) => io,
        None => return Err("SocketIo instance not available".into()),
    };
    let sockets = io.sockets().unwrap();
    let ps = sockets
        .iter()
        .find(|s| s.id.to_string() == pid)
        .ok_or_else(|| "Plugin socket not found in connected sockets".to_string())?;
    let _ = ps.emit("desktop-command", &msg);
    Ok(true)
}

#[tauri::command]
async fn get_plugin_health(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
) -> Result<PluginHealth, String> {
    let app_state = state.inner().clone();
    let st = app_state.read().await;
    let connected = st.plugin_socket.is_some();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let age = st
        .plugin_last_heartbeat_ms
        .map(|hb| now.saturating_sub(hb));
    let stale = connected && age.map(|a| a > 20_000).unwrap_or(true);

    Ok(PluginHealth {
        connected,
        stale,
        last_heartbeat_ms: st.plugin_last_heartbeat_ms,
        age_ms: age,
        protocol: st.plugin_protocol.clone(),
    })
}

#[tauri::command]
async fn get_full_export(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
) -> Result<Option<serde_json::Value>, String> {
    let app_state = state.inner().clone();
    let st = app_state.read().await;
    Ok(st.full_export_cache.clone())
}

#[derive(Serialize)]
struct AnalyticsData {
    total_sessions: u64,
    total_previews: u64,
    active_connections: usize,
}

#[tauri::command]
async fn get_analytics(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
) -> Result<AnalyticsData, String> {
    let app_state = state.inner().clone();
    let st = app_state.read().await;
    let active_connections = st.mobiles.len();
    Ok(AnalyticsData {
        total_sessions: if st.plugin_socket.is_some() { 1 } else { 0 },
        total_previews: if st.design_cache.is_some() { active_connections as u64 } else { 0 },
        active_connections,
    })
}

#[derive(Serialize)]
struct TeamData {
    team_name: String,
    plan: String,
    member_count: u64,
    max_members: u64,
    features: Vec<String>,
}

#[tauri::command]
async fn get_team_info(
    state: tauri::State<'_, Arc<RwLock<AppState>>>,
) -> Result<TeamData, String> {
    let app_state = state.inner().clone();
    let st = app_state.read().await;
    let count = st.mobiles.len() as u64 + if st.plugin_socket.is_some() { 1 } else { 0 };
    Ok(TeamData {
        team_name: "My Desktop Team".into(),
        plan: "team".into(),
        member_count: count,
        max_members: 25,
        features: vec![
            "Unlimited local previews".into(),
            "Desktop + mobile devices".into(),
            "No cloud dependency".into(),
        ],
    })
}

fn emit_event(app_handle: &Option<tauri::AppHandle>, event: &str, payload: impl Serialize + Clone) {
    eprintln!("[emit_event] event={} has_handle={}", event, app_handle.is_some());
    if let Some(handle) = app_handle {
        match handle.emit(event, payload) {
            Ok(_) => eprintln!("[emit_event] {} sent OK", event),
            Err(e) => eprintln!("[emit_event] {} error: {:?}", event, e),
        }
    }
}

fn ns_handler(
    socket: SocketRef,
    state: Arc<RwLock<AppState>>,
    io: socketioxide::SocketIo,
) {
    eprintln!("[ns_handler] socket connected: id={}", socket.id);
    let io1 = io.clone();
    let s1 = state.clone();
    socket.on("join-session", move |_socket: SocketRef, Data::<serde_json::Value>(payload)| {
        eprintln!("[join-session] received role={:?}", payload.get("role"));
        let state = s1.clone();
        let io = io1.clone();
        let sid = _socket.id.to_string();
        let role = payload.get("role").and_then(|v| v.as_str()).unwrap_or("unknown").to_string();
        let session_id: String = payload.get("sessionId").and_then(|v| v.as_str()).unwrap_or("seelo-desktop").to_string();
        let _ = _socket.join(session_id.clone());
        let p = payload.clone();

        tokio::spawn(async move {
                eprintln!("[task] join-session task started...");
            let mut st = state.write().await;
            eprintln!("[task] write lock acquired, role={}", role);
            if role == "plugin" {
                st.plugin_socket = Some(sid.clone());
                st.plugin_last_heartbeat_ms = Some(
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_millis() as u64)
                        .unwrap_or(0),
                );
                st.plugin_protocol = p
                    .get("protocol")
                    .and_then(|v| v.as_str())
                    .map(|v| v.to_string());
                let _ = _socket.emit("join-ack", &serde_json::json!({
                    "ok": true,
                    "roomId": session_id,
                    "role": "plugin"
                }));
                let _ = _socket.emit("room-registered", &serde_json::json!({
                    "roomSecret": st.room_secret.clone().unwrap_or_default(),
                }));
                emit_event(&st.app_handle, "plugin-status", "connected");
                // Backfill currently connected mobiles to freshly connected plugin UI.
                for (mid, m) in st.mobiles.iter() {
                    let _ = _socket.emit(
                        "mobile-connected",
                        &serde_json::json!({
                            "socketId": mid,
                            "deviceName": m.name,
                            "screenWidth": m.width,
                            "screenHeight": m.height
                        }),
                    );
                }
                let _ = _socket.emit("mobile-list", &build_mobile_list(&st));
                emit_event(&st.app_handle, "mobile-list-updated", mobile_items(&st));
                if let Some(cache) = &st.design_cache {
                    let sockets = io.sockets().unwrap();
                    if let Some(ps) = sockets.iter().find(|s| s.id.to_string() == sid) {
                        let _ = ps.emit("design-changed", &serde_json::json!({"design": cache}));
                    }
                }
            }
            if role == "mobile" || role == "viewer" {
                let name = p.get("deviceName").and_then(|v| v.as_str()).unwrap_or("Mobile").to_string();
                let w = p.get("screenWidth").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
                let h = p.get("screenHeight").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
                st.mobiles.insert(sid.clone(), MobileInfo { name: name.clone(), width: w, height: h });
                emit_event(&st.app_handle, "mobile-connected", &serde_json::json!({
                    "socketId": sid.clone(),
                    "deviceName": name,
                    "screenWidth": w,
                    "screenHeight": h
                }));
                let _ = io.emit(
                    "mobile-connected",
                    &serde_json::json!({
                        "socketId": sid.clone(),
                        "deviceName": p.get("deviceName").and_then(|v| v.as_str()).unwrap_or("Mobile"),
                        "screenWidth": w,
                        "screenHeight": h
                    }),
                );
                let _ = io.emit("mobile-list", &build_mobile_list(&st));
                emit_event(&st.app_handle, "mobile-list-updated", mobile_items(&st));

                // Auto trigger a fresh plugin sync whenever a mobile joins,
                // so preview doesn't stay in "waiting" state.
                if let Some(pid) = &st.plugin_socket {
                    let sockets = io.sockets().unwrap();
                    if let Some(ps) = sockets.iter().find(|s| s.id.to_string() == *pid) {
                        let _ = ps.emit("desktop-command", &serde_json::json!({
                            "type": "manual-sync"
                        }));
                    }
                }
            }
        });
    });

    let io2 = io.clone();
    let s2 = state.clone();
    socket.on("cloud-design", move |_: SocketRef, Data::<serde_json::Value>(data)| {
        let state = s2.clone();
        let io = io2.clone();
        tokio::spawn(async move {
            let mut st = state.write().await;
            st.design_cache = Some(data.clone());
            emit_event(&st.app_handle, "design-updated", &data);
            let mobile_ids: Vec<String> = st.mobiles.keys().cloned().collect();
            let sockets = io.sockets().unwrap();
            for mid in &mobile_ids {
                if let Some(ms) = sockets.iter().find(|s| s.id.to_string() == *mid) {
                    let _ = ms.emit("design-changed", &serde_json::json!({"design": data}));
                }
            }
        });
    });

    let s5 = state.clone();
    socket.on("full-export", move |socket: SocketRef, Data::<serde_json::Value>(data)| {
        let _ = socket.broadcast().emit("full-export-data", &data);
        let state = s5.clone();
        let data2 = data.clone();
        tokio::spawn(async move {
            let mut st = state.write().await;
            st.full_export_cache = Some(data2.clone());
            emit_event(&st.app_handle, "full-export-data", &data2);
        });
    });

    let s3 = state.clone();
    socket.on("plugin-heartbeat", move |_: SocketRef, Data::<serde_json::Value>(hb)| {
        let state = s3.clone();
        tokio::spawn(async move {
            let mut st = state.write().await;
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as u64)
                .unwrap_or(0);
            st.plugin_last_heartbeat_ms = Some(now_ms);
            if let Some(proto) = hb.get("protocol").and_then(|v| v.as_str()) {
                st.plugin_protocol = Some(proto.to_string());
            }
        });
    });

    socket.on("command-ack", move |_: SocketRef, Data::<serde_json::Value>(ack)| {
        eprintln!("[plugin-ack] {:?}", ack);
    });

    socket.on("ping", move |socket: SocketRef, Data::<serde_json::Value>(data)| {
        let _ = socket.emit("pong", &serde_json::json!({
            "ts": data.get("ts").and_then(|v| v.as_u64()).unwrap_or_else(|| {
                std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
            })
        }));
    });

    let io7 = io.clone();
    let s9 = state.clone();
    socket.on("request-resize", move |_: SocketRef, Data::<serde_json::Value>(payload)| {
        let io = io7.clone();
        let state = s9.clone();
        tokio::spawn(async move {
            let st = state.read().await;
            let room_secret = st.room_secret.clone().unwrap_or_default();
            let payload_secret = payload.get("roomSecret").and_then(|v| v.as_str()).unwrap_or("");
            if payload_secret.is_empty() || payload_secret != room_secret {
                emit_event(&st.app_handle, "error-msg", serde_json::json!({"message": "Invalid room credentials for resize"}));
                return;
            }
            let _ = io.emit("resize-request", &serde_json::json!({
                "type": "resize-frame",
                "width": payload.get("width").and_then(|v| v.as_u64()).unwrap_or(0),
                "height": payload.get("height").and_then(|v| v.as_u64()).unwrap_or(0),
                "name": payload.get("name").and_then(|v| v.as_str()).unwrap_or(""),
            }));
        });
    });

    let io8 = io.clone();
    let s10 = state.clone();
    socket.on("navigate-frame", move |_: SocketRef, Data::<serde_json::Value>(payload)| {
        let io = io8.clone();
        let state = s10.clone();
        tokio::spawn(async move {
            let st = state.read().await;
            let room_secret = st.room_secret.clone().unwrap_or_default();
            let payload_secret = payload.get("roomSecret").and_then(|v| v.as_str()).unwrap_or("");
            if payload_secret.is_empty() || payload_secret != room_secret {
                emit_event(&st.app_handle, "error-msg", serde_json::json!({"message": "Invalid room credentials for navigation"}));
                return;
            }
            let _ = io.emit("frame-navigation", &serde_json::json!({
                "direction": payload.get("direction").and_then(|v| v.as_str()).unwrap_or("next"),
            }));
        });
    });

    let s4 = state.clone();
    let io4 = io.clone();
    socket.on_disconnect(move |socket: SocketRef| {
        let state = s4.clone();
        let io = io4.clone();
        let sid = socket.id.to_string();
        tokio::spawn(async move {
            let mut st = state.write().await;
            let was_plugin = st.plugin_socket.as_deref() == Some(&sid);
            if was_plugin {
                st.plugin_socket = None;
                st.plugin_last_heartbeat_ms = None;
                st.plugin_protocol = None;
                emit_event(&st.app_handle, "plugin-status", "disconnected");
            }
            if st.mobiles.remove(&sid).is_some() {
                emit_event(&st.app_handle, "mobile-disconnected", &sid);
                let _ = io.emit("mobile-disconnected", &sid);
                let _ = io.emit("mobile-list", &build_mobile_list(&st));
                emit_event(&st.app_handle, "mobile-list-updated", mobile_items(&st));
            }
        });
    });
}

#[tokio::main]
async fn main() {
    let state = Arc::new(RwLock::new(AppState::default()));

    let (svc, io) = socketioxide::SocketIo::new_svc();
    let svc_io = io.clone();
    let svc_state = state.clone();

    io.ns("/", move |socket: SocketRef| {
        ns_handler(socket, svc_state.clone(), svc_io.clone());
    });

    let cors = tower_http::cors::CorsLayer::permissive();
    let router = axum::Router::new()
        .fallback_service(svc)
        .layer(cors);

    let setup_state = state.clone();
    let router_arc = Arc::new(router);

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            Some(vec![]),
        ))
        .manage(state.clone())
        .manage(io)
        .invoke_handler(tauri::generate_handler![
            get_mobiles,
            block_mobile,
            send_to_plugin,
            get_local_ip,
            get_plugin_health,
            get_pairing_qr,
            get_full_export,
            get_analytics,
            get_team_info
        ])
        .setup(move |app| {
            let handle = app.handle().clone();
            let st = setup_state.clone();
            let r = router_arc.clone();

            let secret_path = app.path().app_config_dir().map(|p| p.join("seelo_secret.json"));

            tokio::spawn(async move {
                let mut s = st.write().await;
                s.app_handle = Some(handle.clone());
                // Load persisted room secret
                if let Ok(path) = &secret_path {
                    if let Ok(content) = std::fs::read_to_string(path) {
                        if let Ok(data) = serde_json::from_str::<std::collections::HashMap<String, String>>(&content) {
                            if let Some(secret) = data.get("room_secret") {
                                s.room_secret = Some(secret.clone());
                            }
                        }
                    }
                }
                // Generate and persist secret if not loaded from file
                if s.room_secret.is_none() {
                    let secret = generate_secret();
                    s.room_secret = Some(secret.clone());
                    if let Ok(path) = &secret_path {
                        if let Some(parent) = path.parent() {
                            let _ = std::fs::create_dir_all(parent);
                        }
                        let data = serde_json::json!({"room_secret": secret});
                        let _ = std::fs::write(path, data.to_string());
                    }
                }
                drop(s);

                // Try ports 3000–3099, fallback to OS-assigned
                let listener = 'retry: loop {
                    for port in 3000..=3099 {
                        if let Ok(l) = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port)).await {
                            break 'retry l;
                        }
                    }
                    if let Ok(l) = tokio::net::TcpListener::bind("0.0.0.0:0").await {
                        break 'retry l;
                    }
                    eprintln!("Failed to bind any port, aborting");
                    return;
                };
                let addr = listener.local_addr().unwrap_or(std::net::SocketAddr::new(std::net::IpAddr::V4(std::net::Ipv4Addr::new(127, 0, 0, 1)), 0));
                {
                    let mut s2 = st.write().await;
                    s2.server_port = addr.port();
                    let server_port = s2.server_port;
                    let secret = s2.room_secret.clone().unwrap_or_default();
                    drop(s2);

                    // Start BLE advertising (best-effort)
                    let local_ip = get_local_ip();
                    tokio::spawn(async move {
                        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
                        match ble_advertiser::start(server_port, &local_ip, &secret) {
                            Ok(()) => eprintln!("BLE advertiser started"),
                            Err(e) => eprintln!("BLE advertiser: {e} (non-critical)"),
                        }
                    });
                }
                eprintln!("Socket.io server listening on http://{}", addr);
                if let Err(e) = axum::serve(listener, (*r).clone()).await {
                    eprintln!("Server error: {e}");
                }
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
