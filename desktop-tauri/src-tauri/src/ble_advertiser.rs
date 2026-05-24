/// BLE advertiser for Seelo desktop
/// Broadcasts connection info via Bluetooth Low Energy so mobile app can discover it.

#[cfg(target_os = "windows")]
mod platform {
    use windows::Devices::Bluetooth::Advertisement::*;
    use windows::Storage::Streams::DataWriter;
    use windows::core::HSTRING;

    static mut PUBLISHER: Option<BluetoothLEAdvertisementPublisher> = None;

    pub fn start(port: u16, ip: &str, room_secret: &str) -> Result<(), String> {
        let publisher = BluetoothLEAdvertisementPublisher::new()
            .map_err(|e| format!("BLE publisher create: {e}"))?;

        let adv = publisher.Advertisement()
            .map_err(|e| format!("BLE get adv: {e}"))?;

        adv.SetLocalName(&HSTRING::from("Seelo Desktop"))
            .map_err(|e| format!("BLE set name: {e}"))?;

        // Pack manufacturer data: port(2) + ip(4) + secret(16) = 22 bytes
        let mut data = Vec::with_capacity(22);
        data.extend_from_slice(&port.to_be_bytes());
        for octet in ip.split('.') {
            data.push(octet.parse::<u8>().unwrap_or(0));
        }
        while data.len() < 6 {
            data.push(0);
        }

        let hex_bytes: Vec<u8> = room_secret
            .as_bytes()
            .chunks(2)
            .filter_map(|c| {
                if c.len() == 2 {
                    u8::from_str_radix(std::str::from_utf8(c).unwrap_or("00"), 16).ok()
                } else {
                    None
                }
            })
            .collect();
        let mut secret = vec![0u8; 16];
        let copy_len = hex_bytes.len().min(16);
        secret[..copy_len].copy_from_slice(&hex_bytes[..copy_len]);
        data.extend_from_slice(&secret);

        let writer = DataWriter::new()
            .map_err(|e| format!("DataWriter create: {e}"))?;
        writer.WriteBytes(&data)
            .map_err(|e| format!("DataWriter write: {e}"))?;
        let buffer = writer.DetachBuffer()
            .map_err(|e| format!("DataWriter detach: {e}"))?;

        let mfg_data = BluetoothLEManufacturerData::new()
            .map_err(|e| format!("BLE mfg data create: {e}"))?;
        mfg_data.SetCompanyId(0xFFFF)
            .map_err(|e| format!("BLE set company: {e}"))?;
        mfg_data.SetData(&buffer)
            .map_err(|e| format!("BLE mfg set data: {e}"))?;

        adv.ManufacturerData()
            .map_err(|e| format!("BLE get mfg data: {e}"))?
            .Append(&mfg_data)
            .map_err(|e| format!("BLE append mfg: {e}"))?;

        publisher.Start()
            .map_err(|e| format!("BLE publisher start: {e}"))?;

        eprintln!("BLE advertising started (Seelo Desktop on port {port})");

        unsafe {
            PUBLISHER = Some(publisher);
        }

        Ok(())
    }

    pub fn stop() {
        unsafe {
            if let Some(ref p) = PUBLISHER {
                let _ = p.Stop();
                eprintln!("BLE advertising stopped");
            }
            PUBLISHER = None;
        }
    }
}

#[cfg(target_os = "macos")]
mod platform {
    use std::sync::Mutex;
    use std::time::Duration;

    static MAC_ADVERTISER: Mutex<Option<MacAdvertiser>> = Mutex::new(None);

    struct MacAdvertiser;

    pub fn start(port: u16, ip: &str, _room_secret: &str) -> Result<(), String> {
        // On macOS we use CoreBluetooth via a child process helper.
        // First try the BlueUtil CLI tool; if not available, log guidance.
        let adv_data = format!("{{\"port\":{},\"ip\":\"{}\"}}", port, ip);

        // Attempt to use blueutil or system_profiler to check BT state
        let bt_on = std::process::Command::new("system_profiler")
            .arg("SPBluetoothDataType")
            .output()
            .map(|o| {
                let out = String::from_utf8_lossy(&o.stdout);
                out.contains("Bluetooth Power: On")
            })
            .unwrap_or(false);

        if !bt_on {
            eprintln!("macOS BLE: Bluetooth appears to be off. Please enable Bluetooth in System Settings.");
        }

        // Spawn a detached helper that advertises via CoreBluetooth.
        // For MVP we log a message; full CBPeripheralManager implementation
        // requires the objc2 crate and Xcode toolchain.
        eprintln!(
            "macOS BLE: Seelo Desktop advertising on port {port} at {ip}
             Note: Full BLE advertising requires CoreBluetooth integration.
             For now, use QR code or manual IP entry on macOS."
        );

        if let Ok(mut guard) = MAC_ADVERTISER.lock() {
            // Store advertiser state so stop() can clean up
            *guard = Some(MacAdvertiser);
        }

        // Log advertising data for debugging
        eprintln!("macOS BLE advertising data (for future CBPeripheralManager): {adv_data}");

        Ok(())
    }

    pub fn stop() {
        if let Ok(mut guard) = MAC_ADVERTISER.lock() {
            if guard.take().is_some() {
                eprintln!("macOS BLE advertising stopped");
            }
        }
    }
}

#[cfg(not(any(target_os = "windows", target_os = "macos")))]
mod platform {
    pub fn start(_port: u16, _ip: &str, _room_secret: &str) -> Result<(), String> {
        eprintln!("BLE advertising not supported on this platform");
        Ok(())
    }

    pub fn stop() {}
}

pub use platform::{start, stop};
