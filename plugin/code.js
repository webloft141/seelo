figma.showUI(__html__, { width: 340, height: 520 });

let debounceTimer = null;

(async () => {
    // Required before registering documentchange with dynamic-page
    await figma.loadAllPagesAsync().catch(() => {});
    figma.on("documentchange", (event) => {
        if (debounceTimer) clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => syncSelection(), 700);
    });
})();

figma.on("selectionchange", syncSelection);

async function syncSelection() {
    let selection = figma.currentPage.selection;
    if (selection.length === 0) {
        const firstFrame = figma.currentPage.children.find(
            (n) => n.type === 'FRAME' || n.type === 'COMPONENT' || n.type === 'INSTANCE'
        );
        if (!firstFrame) {
            figma.notify('No frame found. Select a frame to sync.');
            return;
        }
        figma.currentPage.selection = [firstFrame];
        selection = figma.currentPage.selection;
    }

    try {
        let currentNode = selection[0];
        
        // Always export the entire frame even if an inner button is selected
        let rootNode = currentNode;
        while (rootNode && rootNode.parent && rootNode.parent.type !== 'PAGE') {
            rootNode = rootNode.parent;
        }

        // Export as PNG 2x for sharp quality
        const bytes = await rootNode.exportAsync({
            format: 'PNG',
            constraint: { type: 'SCALE', value: 2 },
            contentsOnly: false
        });

        const base64 = figma.base64Encode(bytes);
        
        let videoLayers = [];
        let textLayers = [];
        if ('children' in rootNode) {
            videoLayers = extractVideoLayers(rootNode, rootNode);
            textLayers = extractTextLayers(rootNode, rootNode);
        }

        figma.ui.postMessage({ 
            type: 'selection-updated', 
            data: {
                id: rootNode.id,
                projectId: figma.fileKey || 'local-file',
                width: rootNode.width,
                height: rootNode.height,
                exportScale: 2,
                imageData: `data:image/png;base64,${base64}`,
                videoLayers: videoLayers,
                textLayers: textLayers,
                backgroundColor: extractSolidColor(rootNode)
            } 
        });
    } catch (err) {
        console.error(err);
        figma.notify('Sync failed. Re-select frame and tap SYNC NOW.');
    }
}

function getNodeBounds(node) {
    return node.absoluteRenderBounds || node.absoluteBoundingBox;
}

function extractVideoLayers(node, rootNode) {
    let videos = [];
    if (node.name && node.name.toLowerCase().startsWith('[video]')) {
        const parts = node.name.split(' ');
        const url = parts.length > 1 ? parts[1].trim() : '';
        const bounds = getNodeBounds(node);
        const rootBounds = getNodeBounds(rootNode);
        if (url && bounds && rootBounds) {
            const x = bounds.x - rootBounds.x;
            const y = bounds.y - rootBounds.y;
            videos.push({ id: node.id, url, x, y, width: node.width, height: node.height });
        }
    }
    
    if ('children' in node) {
        for (const child of node.children) {
            videos = videos.concat(extractVideoLayers(child, rootNode));
        }
    }
    return videos;
}

function extractTextLayers(node, rootNode) {
    let texts = [];
    const bounds = getNodeBounds(node);
    const rootBounds = getNodeBounds(rootNode);
    if (node.type === 'TEXT' && bounds && rootBounds) {
        const x = bounds.x - rootBounds.x;
        const y = bounds.y - rootBounds.y;
        const fillColor = extractSolidColor(node);
        texts.push({
            id: node.id,
            characters: node.characters,
            fontFamily: node.fontName ? node.fontName.family : 'System',
            fontStyle: node.fontName ? node.fontName.style : 'Regular',
            fontSize: node.fontSize || 16,
            textAlign: node.textAlignHorizontal || 'LEFT',
            color: fillColor,
            letterSpacing: node.letterSpacing && node.letterSpacing.unit !== 'PERCENT' ? node.letterSpacing.value : 0,
            lineHeight: node.lineHeight && node.lineHeight.unit === 'PIXELS' ? node.lineHeight.value : 0,
            opacity: typeof node.opacity === 'number' ? node.opacity : 1,
            x: x || 0, y: y || 0, width: node.width || 0, height: node.height || 0
        });
    }
    if ('children' in node) {
        for (const child of node.children) {
            texts = texts.concat(extractTextLayers(child, rootNode));
        }
    }
    return texts;
}

function extractSolidColor(node) {
    try {
        if (!node.fills || node.fills.length === 0) return '#ffffff';
        for (const fill of node.fills) {
            if (fill.type === 'SOLID' && fill.color) {
                const r = Math.round(fill.color.r * 255);
                const g = Math.round(fill.color.g * 255);
                const b = Math.round(fill.color.b * 255);
                const a = typeof fill.opacity === 'number' ? fill.opacity : 1;
                if (a < 1) return `rgba(${r},${g},${b},${a})`;
                return `#${r.toString(16).padStart(2,'0')}${g.toString(16).padStart(2,'0')}${b.toString(16).padStart(2,'0')}`;
            }
        }
        return '#ffffff';
    } catch (e) { return '#ffffff'; }
}

figma.ui.onmessage = async (msg) => {
    const selection = figma.currentPage.selection;
    if (msg.type === 'resize') figma.ui.resize(msg.width, msg.height);
    if (msg.type === 'resize-frame') {
        let target = selection.length > 0 ? selection[0] : null;
        if (!target) {
            target = figma.currentPage.children.find(
                (n) => n.type === 'FRAME' || n.type === 'COMPONENT' || n.type === 'INSTANCE'
            ) || null;
            if (target) figma.currentPage.selection = [target];
        }
        if (target && (target.type === "FRAME" || target.type === "COMPONENT" || target.type === "INSTANCE")) {
            target.resize(msg.width, msg.height);
            figma.notify(`Auto-Resized to ${msg.name}`);
            syncSelection();
        }
    }
    if (msg.type === 'manual-sync') await syncSelection();
    if (msg.type === 'set-preview-model') {
        const deviceModels = {
            'Pixel 8': { w: 393, h: 852 },
            'iPhone 15': { w: 393, h: 852 },
            'Galaxy S24': { w: 360, h: 780 },
            'iPhone SE': { w: 375, h: 667 },
            'iPad Mini': { w: 744, h: 1133 },
        };
        const model = deviceModels[msg.model];
        if (model && selection.length > 0) {
            let target = selection[0];
            while (target && target.parent && target.parent.type !== 'PAGE') {
                target = target.parent;
            }
            if (target && (target.type === 'FRAME' || target.type === 'COMPONENT' || target.type === 'INSTANCE')) {
                target.resize(model.w, model.h);
                figma.notify(`Resized to ${msg.model} (${model.w}\u00D7${model.h})`);
                syncSelection();
            }
        }
    }
    if (msg.type === 'navigate-frame') {
        const frames = figma.currentPage.children.filter(n => n.type === 'FRAME' || n.type === 'COMPONENT' || n.type === 'INSTANCE');
        if (frames.length === 0) return;
        
        frames.sort((a, b) => a.x - b.x);
        
        let currentIndex = -1;
        if (selection.length > 0) {
            let currentNode = selection[0];
            while (currentNode && currentNode.parent && currentNode.parent.type !== 'PAGE') {
                currentNode = currentNode.parent;
            }
            if (currentNode) {
                currentIndex = frames.findIndex(f => f.id === currentNode.id);
            }
        }
        
        let newIndex = 0;
        if (currentIndex !== -1) {
            if (msg.direction === 'next') newIndex = (currentIndex + 1) % frames.length;
            else if (msg.direction === 'prev') newIndex = (currentIndex - 1 + frames.length) % frames.length;
        }
        
        const nextFrame = frames[newIndex];
        figma.currentPage.selection = [nextFrame];
        figma.viewport.scrollAndZoomIntoView([nextFrame]);
    }
    if (msg.type === 'desktop-command') {
        if (msg.command === 'full-export') {
            await exportFullDocument();
        } else if (msg.command === 'manual-sync') {
            syncSelection();
        } else if (msg.command === 'select-frame' && msg.frameId) {
            const node = figma.getNodeById(msg.frameId);
            if (node && node.type !== 'DOCUMENT' && node.type !== 'PAGE') {
                figma.currentPage.selection = [node];
                figma.viewport.scrollAndZoomIntoView([node]);
            }
        }
    }
};

function getNodeInfo(node) {
    const info = {
        id: node.id,
        name: node.name,
        type: node.type,
        visible: node.visible !== false
    };
    if ('width' in node) { info.width = node.width; info.height = node.height; }
    if ('x' in node) { info.x = node.x; info.y = node.y; }
    if (node.type === 'TEXT') {
        info.characters = node.characters;
        info.fontSize = node.fontSize || 16;
    }
    return info;
}

async function exportFullDocument() {
    try {
        const pages = [];
        for (const page of figma.root.children) {
            if (page.type !== 'PAGE') continue;
            const frames = [];
            function collectFramesDeep(node) {
                const isFrameLike = node.type === 'FRAME' || node.type === 'COMPONENT' || node.type === 'INSTANCE';
                if (isFrameLike) {
                    const layers = [];
                    if ('children' in node) {
                        function collectLayers(n) {
                            for (const child of n.children) {
                                const childIsFrameLike = child.type === 'FRAME' || child.type === 'COMPONENT' || child.type === 'INSTANCE';
                                if (!childIsFrameLike) {
                                    layers.push(getNodeInfo(child));
                                }
                                if ('children' in child) collectLayers(child);
                            }
                        }
                        collectLayers(node);
                    }
                    frames.push({
                        name: node.name,
                        id: node.id,
                        width: node.width,
                        height: node.height,
                        x: node.x,
                        y: node.y,
                        layers
                    });
                    return;
                }
                if ('children' in node) {
                    for (const child of node.children) collectFramesDeep(child);
                }
            }
            for (const node of page.children) collectFramesDeep(node);
            pages.push({ name: page.name, id: page.id, frames });
        }

        const doc = { pages, totalFrames: pages.reduce((s, p) => s + p.frames.length, 0) };

        figma.ui.postMessage({ type: 'full-export', data: doc });
        if (doc.totalFrames === 0) {
            figma.notify('Export completed but found 0 frames. Put content inside Frame/Component/Instance.');
        } else {
            figma.notify(`Exported ${doc.totalFrames} frames`);
        }
    } catch (err) {
        console.error(err);
        figma.notify('Export failed');
    }
}
