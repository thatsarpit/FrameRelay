import AppKit
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(size) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 194, yRadius: 194).fill()
    let frame = NSBezierPath(); frame.lineWidth = 44; frame.lineCapStyle = .round; frame.lineJoinStyle = .round
    for (x, y, dx, dy) in [(300.0,300.0,1.0,1.0), (724,300,-1,1), (300,724,1,-1), (724,724,-1,-1)] {
        frame.move(to: NSPoint(x:x+dx*104,y:y)); frame.line(to:NSPoint(x:x,y:y)); frame.line(to:NSPoint(x:x,y:y+dy*104))
    }
    NSColor(calibratedRed:0.97,green:0.96,blue:0.93,alpha:1).setStroke(); frame.stroke()
    NSColor(calibratedRed:0.86,green:0.24,blue:0.16,alpha:1).setFill()
    NSBezierPath(ovalIn:NSRect(x:464,y:464,width:96,height:96)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let name: String
    switch size { case 16: name="icon_16x16"; case 32: name="icon_16x16@2x"; case 64: name="icon_32x32@2x"; case 128: name="icon_128x128"; case 256: name="icon_128x128@2x"; case 512: name="icon_256x256@2x"; default: name="icon_512x512@2x" }
    try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(name+".png"))
    if size == 32 || size == 256 || size == 512 { try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent("icon_\(size)x\(size).png")) }
}
