// Gera AppIcon.iconset (PNGs) do The Styk a partir do logo.png fornecido.
// Uso: swiftc -o /tmp/make_icon tools/make_icon.swift && /tmp/make_icon <dir_iconset>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let fm = FileManager.default
let logoPaths = ["assets/logo.png", "../logo.png", "logo.png"]
var selectedLogoPath: String? = nil

for path in logoPaths {
    if fm.fileExists(atPath: path) {
        selectedLogoPath = path
        break
    }
}

guard let logoPath = selectedLogoPath, let logoImage = NSImage(contentsOfFile: logoPath) else {
    print("Erro: não foi possível encontrar ou carregar o arquivo logo.png")
    exit(1)
}

func resizeImage(image: NSImage, px: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    
    // Configuração de interpolação de alta qualidade para redimensionamento
    NSGraphicsContext.current?.imageInterpolation = .high
    
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
    
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(CGFloat, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
    (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
    (512, "512x512"), (1024, "512x512@2x"),
]

for (px, name) in sizes {
    let rep = resizeImage(image: logoImage, px: px)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}

// Ícone da barra de menus (StatusBarIcon.png e StatusBarIcon@2x.png)
let statusBarSizes: [(CGFloat, String)] = [
    (18, "StatusBarIcon.png"),
    (36, "StatusBarIcon@2x.png")
]

let statusBarPaths = ["../StatusBarIconSource.png", "StatusBarIconSource.png"]
var selectedStatusBarPath: String? = nil
for path in statusBarPaths {
    if fm.fileExists(atPath: path) {
        selectedStatusBarPath = path
        break
    }
}

let statusBarSourceImage: NSImage
if let sbPath = selectedStatusBarPath, let sbImg = NSImage(contentsOfFile: sbPath) {
    statusBarSourceImage = sbImg
} else {
    statusBarSourceImage = logoImage
}

for (px, name) in statusBarSizes {
    let rep = resizeImage(image: statusBarSourceImage, px: px)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

print("iconset ok: \(outDir)")
