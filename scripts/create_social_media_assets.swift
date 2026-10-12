import AppKit
import AVFoundation
import CoreText
import CoreVideo
import ImageIO
import UniformTypeIdentifiers

private let designWidth: CGFloat = 1080
private let dark = rgb(0x19302B)
private let green = rgb(0x17654C)
private let lightGreen = rgb(0xD1E86D)
private let canvas = rgb(0xF2F5ED)
private let muted = rgb(0x72817A)
private let white = rgb(0xFFFFFF)

private func rgb(_ value: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
    )
}

private func rgba(_ value: UInt32, alpha: CGFloat) -> CGColor {
    CGColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

private func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat, canvasHeight: CGFloat) -> CGRect {
    CGRect(x: x, y: canvasHeight - top - height, width: width, height: height)
}

private func rounded(_ context: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat, fill: CGColor, canvasHeight: CGFloat, stroke: CGColor? = nil, lineWidth: CGFloat = 1) {
    let path = CGPath(roundedRect: rect(x, y, width, height, canvasHeight: canvasHeight), cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
    context.setFillColor(fill)
    context.fillPath()
    if let stroke {
        context.addPath(path)
        context.setStrokeColor(stroke)
        context.setLineWidth(lineWidth)
        context.strokePath()
    }
}

private func circle(_ context: CGContext, x: CGFloat, y: CGFloat, diameter: CGFloat, fill: CGColor?, stroke: CGColor? = nil, lineWidth: CGFloat = 1, canvasHeight: CGFloat) {
    let bounds = rect(x, y, diameter, diameter, canvasHeight: canvasHeight)
    if let fill {
        context.setFillColor(fill)
        context.fillEllipse(in: bounds)
    }
    if let stroke {
        context.setStrokeColor(stroke)
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: bounds)
    }
}

private func text(_ context: CGContext, _ value: String, x: CGFloat, top: CGFloat, size: CGFloat, color: CGColor, weight: String = "AvenirNext-DemiBold", canvasHeight: CGFloat) {
    let font = CTFontCreateWithName(weight as CFString, size, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
    context.saveGState()
    context.textPosition = CGPoint(x: x, y: canvasHeight - top - size * 0.88)
    CTLineDraw(line, context)
    context.restoreGState()
}

private func paragraph(_ context: CGContext, _ lines: [String], x: CGFloat, top: CGFloat, size: CGFloat, leading: CGFloat, color: CGColor, weight: String = "AvenirNext-DemiBold", canvasHeight: CGFloat) {
    for (index, line) in lines.enumerated() {
        text(context, line, x: x, top: top + CGFloat(index) * leading, size: size, color: color, weight: weight, canvasHeight: canvasHeight)
    }
}

private func drawLogo(_ context: CGContext, image: CGImage, x: CGFloat, y: CGFloat, size: CGFloat, canvasHeight: CGFloat) {
    rounded(context, x: x - 2, y: y - 2, width: size + 4, height: size + 4, radius: size * 0.22, fill: white, canvasHeight: canvasHeight)
    context.saveGState()
    context.addPath(CGPath(roundedRect: rect(x, y, size, size, canvasHeight: canvasHeight), cornerWidth: size * 0.2, cornerHeight: size * 0.2, transform: nil))
    context.clip()
    context.draw(image, in: rect(x, y, size, size, canvasHeight: canvasHeight))
    context.restoreGState()
}

private func drawBrand(_ context: CGContext, logo: CGImage, y: CGFloat, canvasHeight: CGFloat, onDark: Bool, size: CGFloat = 74) {
    drawLogo(context, image: logo, x: 72, y: y, size: size, canvasHeight: canvasHeight)
    text(context, "Wertweit", x: 72 + size + 22, top: y + size * 0.15, size: 34, color: onDark ? white : dark, canvasHeight: canvasHeight)
    text(context, "WÄHRUNGSRECHNER FÜR REISEN", x: 72 + size + 22, top: y + size * 0.61, size: 13, color: onDark ? lightGreen : green, canvasHeight: canvasHeight)
}

private func drawDevice(_ context: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, canvasHeight: CGFloat, variant: Int = 0) {
    rounded(context, x: x, y: y, width: width, height: height, radius: width * 0.11, fill: dark, canvasHeight: canvasHeight)
    let inset = width * 0.035
    rounded(context, x: x + inset, y: y + inset, width: width - inset * 2, height: height - inset * 2, radius: width * 0.085, fill: canvas, canvasHeight: canvasHeight)
    rounded(context, x: x + width * 0.37, y: y + width * 0.07, width: width * 0.26, height: width * 0.035, radius: width * 0.02, fill: dark, canvasHeight: canvasHeight)

    let left = x + width * 0.09
    let available = width * 0.82
    text(context, "Wertweit", x: left, top: y + width * 0.18, size: width * 0.075, color: dark, canvasHeight: canvasHeight)
    text(context, variant == 1 ? "REISEPLANUNG" : "WÄHRUNGSRECHNER", x: left, top: y + width * 0.29, size: width * 0.033, color: muted, canvasHeight: canvasHeight)

    rounded(context, x: left, y: y + width * 0.39, width: available, height: height * 0.18, radius: width * 0.045, fill: white, canvasHeight: canvasHeight)
    text(context, "DEIN BETRAG", x: left + width * 0.06, top: y + width * 0.44, size: width * 0.03, color: muted, canvasHeight: canvasHeight)
    text(context, "1.000,00", x: left + width * 0.06, top: y + width * 0.49, size: width * 0.085, color: dark, canvasHeight: canvasHeight)
    text(context, "EUR", x: left + width * 0.66, top: y + width * 0.505, size: width * 0.04, color: green, canvasHeight: canvasHeight)

    rounded(context, x: left, y: y + width * 0.61, width: available, height: height * 0.13, radius: width * 0.04, fill: green, canvasHeight: canvasHeight)
    text(context, "EUR", x: left + width * 0.08, top: y + width * 0.655, size: width * 0.055, color: white, canvasHeight: canvasHeight)
    text(context, "→", x: left + width * 0.39, top: y + width * 0.65, size: width * 0.06, color: lightGreen, canvasHeight: canvasHeight)
    text(context, "USD", x: left + width * 0.58, top: y + width * 0.655, size: width * 0.055, color: white, canvasHeight: canvasHeight)

    rounded(context, x: left, y: y + width * 0.78, width: available, height: height * 0.12, radius: width * 0.035, fill: white, canvasHeight: canvasHeight)
    text(context, variant == 1 ? "Reisebudget" : "Referenzkurs", x: left + width * 0.06, top: y + width * 0.81, size: width * 0.038, color: dark, canvasHeight: canvasHeight)
    text(context, variant == 1 ? "Richtwerte im Blick" : "Kurse vergleichen", x: left + width * 0.06, top: y + width * 0.865, size: width * 0.033, color: green, weight: "AvenirNext-Regular", canvasHeight: canvasHeight)
}

private func background(_ context: CGContext, width: CGFloat, height: CGFloat, darkMode: Bool) {
    let colors = darkMode ? [rgb(0x102820), rgb(0x1B5A43)] : [rgb(0xF8F9F4), canvas]
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) else { return }
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
}

private func drawPhotoBackground(_ context: CGContext, image: CGImage, time: Double, canvasHeight: CGFloat) {
    let scale = max(designWidth / CGFloat(image.width), canvasHeight / CGFloat(image.height))
    let zoom = 1.02 + CGFloat(time.truncatingRemainder(dividingBy: 4) / 4) * 0.055
    let imageWidth = CGFloat(image.width) * scale * zoom
    let imageHeight = CGFloat(image.height) * scale * zoom
    let panX = CGFloat(sin(time * 0.38)) * 24

    context.saveGState()
    context.clip(to: rect(0, 0, designWidth, canvasHeight, canvasHeight: canvasHeight))
    context.draw(image, in: rect((designWidth - imageWidth) / 2 + panX, (canvasHeight - imageHeight) / 2, imageWidth, imageHeight, canvasHeight: canvasHeight))
    context.restoreGState()

    let shades = [rgba(0x102820, alpha: 0.54), rgba(0x102820, alpha: 0.14), rgba(0x102820, alpha: 0.66)]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: shades as CFArray, locations: [0, 0.52, 1]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvasHeight), end: CGPoint(x: 0, y: 0), options: [])
    }
}

private func drawFeedPoster(_ context: CGContext, logo: CGImage, height: CGFloat, portrait: Bool) {
    background(context, width: designWidth, height: height, darkMode: false)
    circle(context, x: 640, y: 145, diameter: 520, fill: nil, stroke: rgb(0xDDE7D8), lineWidth: 2, canvasHeight: height)
    circle(context, x: 690, y: 195, diameter: 420, fill: nil, stroke: rgb(0xE5ECE2), lineWidth: 2, canvasHeight: height)
    drawBrand(context, logo: logo, y: 66, canvasHeight: height, onDark: false, size: 68)
    rounded(context, x: 72, y: 205, width: 320, height: 48, radius: 24, fill: lightGreen, canvasHeight: height)
    text(context, "FÜR DEINE NÄCHSTE REISE", x: 96, top: 220, size: 16, color: dark, canvasHeight: height)
    paragraph(context, ["Währungswechsel.", "Klarer Überblick."], x: 72, top: 292, size: portrait ? 61 : 58, leading: portrait ? 76 : 70, color: dark, canvasHeight: height)
    text(context, "Kurse, Gebühren und Reisebudgets", x: 76, top: 465, size: 25, color: muted, weight: "AvenirNext-Regular", canvasHeight: height)
    text(context, "an einem Ort im Blick behalten.", x: 76, top: 502, size: 25, color: muted, weight: "AvenirNext-Regular", canvasHeight: height)

    let deviceY: CGFloat = portrait ? 620 : 585
    let deviceH: CGFloat = portrait ? 610 : 530
    drawDevice(context, x: 350, y: deviceY, width: 380, height: deviceH, canvasHeight: height)
    rounded(context, x: 72, y: deviceY + 82, width: 300, height: 140, radius: 25, fill: dark, canvasHeight: height)
    text(context, "EUR → USD", x: 98, top: deviceY + 108, size: 23, color: lightGreen, canvasHeight: height)
    text(context, "Einfach vergleichen.", x: 98, top: deviceY + 151, size: 19, color: white, weight: "AvenirNext-Regular", canvasHeight: height)

    let footerY = height - 114
    rounded(context, x: 72, y: footerY, width: 350, height: 58, radius: 29, fill: green, canvasHeight: height)
    text(context, "Wertweit entdecken", x: 102, top: footerY + 17, size: 20, color: white, canvasHeight: height)
    text(context, "EZB-Referenzkurse · Reiseangaben sind Richtwerte", x: 72, top: height - 38, size: 13, color: muted, weight: "AvenirNext-Regular", canvasHeight: height)
}

private func drawStoryPoster(_ context: CGContext, logo: CGImage, height: CGFloat, travelFocus: Bool) {
    background(context, width: designWidth, height: height, darkMode: true)
    circle(context, x: 600, y: 200, diameter: 700, fill: nil, stroke: rgb(0x2F7358), lineWidth: 2, canvasHeight: height)
    circle(context, x: 680, y: 280, diameter: 540, fill: nil, stroke: rgb(0x286448), lineWidth: 2, canvasHeight: height)
    drawBrand(context, logo: logo, y: 86, canvasHeight: height, onDark: true, size: 76)

    rounded(context, x: 72, y: 285, width: 240, height: 48, radius: 24, fill: lightGreen, canvasHeight: height)
    text(context, travelFocus ? "FÜR UNTERWEGS" : "DEIN GELD. DEINE REISE.", x: 96, top: 300, size: 15, color: dark, canvasHeight: height)
    paragraph(context, travelFocus ? ["Reisen. Wechseln.", "Besser planen."] : ["Währungen", "besser verstehen."], x: 72, top: 376, size: 70, leading: 84, color: white, canvasHeight: height)
    text(context, travelFocus ? "Wertweit hilft beim Überblick." : "Wertweit für deine nächste Reise.", x: 76, top: 566, size: 24, color: rgb(0xC6D8CE), weight: "AvenirNext-Regular", canvasHeight: height)

    let deviceX: CGFloat = travelFocus ? 400 : 470
    let deviceY: CGFloat = 700
    let deviceW: CGFloat = travelFocus ? 440 : 390
    let deviceH: CGFloat = travelFocus ? 700 : 660
    drawDevice(context, x: deviceX, y: deviceY, width: deviceW, height: deviceH, canvasHeight: height, variant: travelFocus ? 1 : 0)

    let labels = travelFocus ? ["Länder-Budgets", "Kaufkraft-Richtwerte", "Trinkgeld im Blick"] : ["Kurse vergleichen", "Gebühren einordnen", "Verläufe ansehen"]
    for (index, label) in labels.enumerated() {
        let top = CGFloat(760 + index * 112)
        circle(context, x: 78, y: top + 4, diameter: 32, fill: lightGreen, canvasHeight: height)
        text(context, "✓", x: 86, top: top + 7, size: 18, color: dark, canvasHeight: height)
        text(context, label, x: 126, top: top + 5, size: 20, color: white, weight: "AvenirNext-Regular", canvasHeight: height)
    }

    rounded(context, x: 72, y: 1570, width: 460, height: 76, radius: 38, fill: lightGreen, canvasHeight: height)
    text(context, "Jetzt Wertweit entdecken", x: 108, top: 1595, size: 23, color: dark, canvasHeight: height)
    text(context, "Referenzkurse, keine Finanzberatung. Reiseangaben sind Richtwerte.", x: 72, top: 1776, size: 13, color: rgb(0xC6D8CE), weight: "AvenirNext-Regular", canvasHeight: height)
}

private func drawSquarePoster(_ context: CGContext, logo: CGImage, height: CGFloat) {
    background(context, width: designWidth, height: height, darkMode: true)
    circle(context, x: 560, y: 220, diameter: 620, fill: nil, stroke: rgb(0x2C7054), lineWidth: 2, canvasHeight: height)
    drawBrand(context, logo: logo, y: 58, canvasHeight: height, onDark: true, size: 70)
    rounded(context, x: 72, y: 196, width: 265, height: 46, radius: 23, fill: lightGreen, canvasHeight: height)
    text(context, "KURSE IM BLICK", x: 96, top: 210, size: 15, color: dark, canvasHeight: height)
    paragraph(context, ["Weniger raten.", "Besser vergleichen."], x: 72, top: 280, size: 58, leading: 71, color: white, canvasHeight: height)
    text(context, "Währungen und Wechselkosten", x: 76, top: 444, size: 21, color: rgb(0xC6D8CE), weight: "AvenirNext-Regular", canvasHeight: height)
    text(context, "verständlicher einschätzen.", x: 76, top: 476, size: 21, color: rgb(0xC6D8CE), weight: "AvenirNext-Regular", canvasHeight: height)
    drawDevice(context, x: 360, y: 555, width: 360, height: 430, canvasHeight: height)
    rounded(context, x: 72, y: 730, width: 285, height: 110, radius: 22, fill: lightGreen, canvasHeight: height)
    text(context, "EUR → USD", x: 98, top: 750, size: 24, color: dark, canvasHeight: height)
    text(context, "Kurse. Gebühren. Verlauf.", x: 98, top: 792, size: 16, color: green, weight: "AvenirNext-Regular", canvasHeight: height)
    text(context, "Wertweit · EZB-Referenzkurse", x: 72, top: 1010, size: 16, color: rgb(0xC6D8CE), weight: "AvenirNext-Regular", canvasHeight: height)
}

private func drawPhotoPoster(_ context: CGContext, logo: CGImage, image: CGImage, height: CGFloat, headline: [String], detail: String, story: Bool) {
    drawPhotoBackground(context, image: image, time: 0, canvasHeight: height)

    let brandSize: CGFloat = story ? 74 : 60
    drawBrand(context, logo: logo, y: story ? 76 : 48, canvasHeight: height, onDark: true, size: brandSize)

    let badgeTop: CGFloat = story ? 292 : 176
    rounded(context, x: 72, y: badgeTop, width: 315, height: 48, radius: 24, fill: lightGreen, canvasHeight: height)
    text(context, story ? "FÜR DEINE NÄCHSTE REISE" : "WERTWEIT FÜR UNTERWEGS", x: 94, top: badgeTop + 15, size: 14, color: dark, canvasHeight: height)

    let headlineTop: CGFloat = story ? 388 : 254
    let headlineSize: CGFloat = story ? 70 : 59
    paragraph(context, headline, x: 72, top: headlineTop, size: headlineSize, leading: headlineSize * 1.12, color: white, canvasHeight: height)
    text(context, detail, x: 76, top: headlineTop + CGFloat(headline.count) * headlineSize * 1.12 + 15, size: story ? 23 : 20, color: rgb(0xE3ECE5), weight: "AvenirNext-Regular", canvasHeight: height)

    let panelY: CGFloat = story ? 940 : 650
    let panelHeight: CGFloat = story ? 206 : 180
    rounded(context, x: 72, y: panelY, width: story ? 570 : 520, height: panelHeight, radius: 28, fill: rgba(0x102820, alpha: 0.78), canvasHeight: height, stroke: rgba(0xFFFFFF, alpha: 0.22), lineWidth: 1)
    text(context, "WERTWEIT IM ÜBERBLICK", x: 102, top: panelY + 27, size: 14, color: lightGreen, canvasHeight: height)
    text(context, "EUR", x: 102, top: panelY + 78, size: 31, color: white, canvasHeight: height)
    text(context, "→", x: 223, top: panelY + 76, size: 33, color: lightGreen, canvasHeight: height)
    text(context, "USD", x: 280, top: panelY + 78, size: 31, color: white, canvasHeight: height)
    text(context, "Kurse, Gebühren und Reise-Richtwerte", x: 102, top: panelY + 137, size: 17, color: rgb(0xE3ECE5), weight: "AvenirNext-Regular", canvasHeight: height)

    let buttonTop = height - (story ? 306 : 190)
    rounded(context, x: 72, y: buttonTop, width: story ? 478 : 430, height: 72, radius: 36, fill: lightGreen, canvasHeight: height)
    text(context, "Wertweit entdecken", x: 108, top: buttonTop + 23, size: 21, color: dark, canvasHeight: height)
    text(context, "EZB-Referenzkurse · Reiseangaben sind Richtwerte", x: 72, top: height - 66, size: 13, color: rgb(0xE3ECE5), weight: "AvenirNext-Regular", canvasHeight: height)
}

private func drawPhotoVideoFrame(_ context: CGContext, time: Double, logo: CGImage, photos: [CGImage], variant: Int) {
    let height: CGFloat = 1920
    let scene = min(Int(time / 4), 2)
    let progress = (time.truncatingRemainder(dividingBy: 4)) / 4
    let photoOrder = variant == 0 ? [0, 1, 2] : [2, 0, 1]
    drawPhotoBackground(context, image: photos[photoOrder[scene]], time: time, canvasHeight: height)
    drawBrand(context, logo: logo, y: 78, canvasHeight: height, onDark: true, size: 72)

    let headlines = variant == 0
        ? [["Deine Reise.", "Dein Überblick."], ["Wechselkurse.", "Klar vergleichen."], ["Wertweit.", "Für unterwegs."]]
        : [["Fernweh im", "Blick behalten."], ["Gebühren vor", "dem Wechseln."], ["Gut planen.", "Entspannt reisen."]]
    let details = variant == 0
        ? ["Vor der Reise einfach umrechnen.", "Angebote besser einschätzen.", "Reise-Richtwerte im Blick behalten."]
        : ["Währungen klarer verstehen.", "Kurse und Kosten vergleichen.", "Wertweit hilft unterwegs."]

    let slide = CGFloat((1 - progress) * 20)
    paragraph(context, headlines[scene], x: 72, top: 380 + slide, size: 66, leading: 80, color: white, canvasHeight: height)
    text(context, details[scene], x: 76, top: 562 + slide, size: 22, color: rgb(0xE3ECE5), weight: "AvenirNext-Regular", canvasHeight: height)

    rounded(context, x: 72, y: 1010, width: 355, height: 92, radius: 24, fill: rgba(0x102820, alpha: 0.8), canvasHeight: height, stroke: rgba(0xFFFFFF, alpha: 0.2), lineWidth: 1)
    text(context, scene == 0 ? "EUR → USD" : scene == 1 ? "Kurse vergleichen" : "Reisebudget planen", x: 102, top: 1040, size: 21, color: lightGreen, canvasHeight: height)

    let ctaColor = scene == 2 ? lightGreen : rgba(0x102820, alpha: 0.72)
    let ctaText = scene == 2 ? dark : white
    rounded(context, x: 72, y: 1608, width: 500, height: 82, radius: 41, fill: ctaColor, canvasHeight: height)
    text(context, scene == 2 ? "Wertweit entdecken" : "Für deine nächste Reise", x: 108, top: 1635, size: 22, color: ctaText, canvasHeight: height)
    text(context, "EZB-Referenzkurse · Keine Finanzberatung", x: 72, top: 1776, size: 14, color: rgb(0xE3ECE5), weight: "AvenirNext-Regular", canvasHeight: height)
}

private func makeContext(width: Int, height: Int, buffer: UnsafeMutableRawPointer? = nil, bytesPerRow: Int? = nil) -> CGContext {
    CGContext(
        data: buffer,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow ?? width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    )!
}

private func savePNG(output: URL, width: Int, height: Int, draw: (CGContext, CGFloat) -> Void) throws {
    let bitmap = makeContext(width: width, height: height)
    draw(bitmap, CGFloat(height))
    guard let image = bitmap.makeImage(), let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "SocialAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG could not be created: \(output.lastPathComponent)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "SocialAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG could not be saved: \(output.lastPathComponent)"])
    }
}

private func drawVideoFrame(_ context: CGContext, time: Double, logo: CGImage, variant: Int) {
    let height: CGFloat = 1920
    let phase = time / 12
    let scene = min(Int(time / 4), 2)
    let progress = (time.truncatingRemainder(dividingBy: 4)) / 4
    background(context, width: designWidth, height: height, darkMode: variant == 0 || scene != 1)

    let orbX = CGFloat(590 + sin(time * 0.7) * 70)
    circle(context, x: orbX, y: CGFloat(330 + cos(time * 0.5) * 35), diameter: 660, fill: nil, stroke: rgb(variant == 0 || scene != 1 ? 0x2E7457 : 0xDDE7D8), lineWidth: 3, canvasHeight: height)
    circle(context, x: orbX + 54, y: CGFloat(384 + cos(time * 0.5) * 35), diameter: 552, fill: nil, stroke: rgb(variant == 0 || scene != 1 ? 0x286448 : 0xE5ECE2), lineWidth: 2, canvasHeight: height)
    drawBrand(context, logo: logo, y: 84, canvasHeight: height, onDark: variant == 0 || scene != 1, size: 74)

    let lightMode = variant == 1 && scene == 1
    let primary = lightMode ? dark : white
    let secondary = lightMode ? muted : rgb(0xC6D8CE)
    let headings = variant == 0
        ? [["Währungen.", "Klarer."], ["Kurse vergleichen.", "Gebühren verstehen."], ["Reisebudget.", "Besser planen."]]
        : [["Vor der Reise", "gut vorbereitet."], ["Wechselkosten", "besser einordnen."], ["Wertweit.", "Für unterwegs."]]
    let details = variant == 0
        ? ["Dein Geld im Überblick.", "Referenzkurse und Vergleiche.", "Richtwerte für dein Reiseziel."]
        : ["Währungen einfach umrechnen.", "Gebühren sichtbar vergleichen.", "Reiseinfos an einem Ort."]
    let slide = CGFloat((1 - progress) * 36)
    paragraph(context, headings[scene], x: 72, top: 375 + slide, size: 66, leading: 80, color: primary, canvasHeight: height)
    text(context, details[scene], x: 76, top: 558 + slide, size: 23, color: secondary, weight: "AvenirNext-Regular", canvasHeight: height)

    let deviceProgress = min(1, max(0, (progress - 0.08) / 0.38))
    let deviceX = 280 + CGFloat((1 - deviceProgress) * 430)
    drawDevice(context, x: deviceX, y: 705, width: 455, height: 780, canvasHeight: height, variant: scene == 2 ? 1 : 0)

    if scene == 0 {
        rounded(context, x: 62, y: 1040, width: 250, height: 88, radius: 22, fill: lightGreen, canvasHeight: height)
        text(context, "EUR → USD", x: 87, top: 1066, size: 22, color: dark, canvasHeight: height)
    } else if scene == 1 {
        rounded(context, x: 65, y: 1035, width: 290, height: 86, radius: 22, fill: lightGreen, canvasHeight: height)
        text(context, "Gebühren vergleichen", x: 88, top: 1060, size: 18, color: dark, canvasHeight: height)
    } else {
        rounded(context, x: 65, y: 1035, width: 310, height: 86, radius: 22, fill: lightGreen, canvasHeight: height)
        text(context, "Reisebudgets ansehen", x: 88, top: 1060, size: 18, color: dark, canvasHeight: height)
    }

    let ctaColor = lightMode ? green : lightGreen
    let ctaText = lightMode ? white : dark
    rounded(context, x: 72, y: 1610, width: 520, height: 82, radius: 41, fill: ctaColor, canvasHeight: height)
    text(context, scene == 2 ? "Wertweit entdecken" : "Für deine nächste Reise", x: 110, top: 1637, size: 22, color: ctaText, canvasHeight: height)
    text(context, "EZB-Referenzkurse · Keine Finanzberatung", x: 72, top: 1776, size: 14, color: secondary, weight: "AvenirNext-Regular", canvasHeight: height)
    _ = phase
}

private func makeVideo(output: URL, logo: CGImage, variant: Int, photoCampaign: [CGImage]? = nil) throws {
    let width = 720
    let height = 1280
    let fps: Int32 = 24
    let frameCount = Int(fps) * 12
    try? FileManager.default.removeItem(at: output)
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 3_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        ]
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
    guard writer.canAdd(input) else {
        throw NSError(domain: "SocialAssets", code: 3, userInfo: [NSLocalizedDescriptionKey: "Video encoder input could not be attached."])
    }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "SocialAssets", code: 4) }
    writer.startSession(atSourceTime: .zero)
    guard let pool = adaptor.pixelBufferPool else { throw NSError(domain: "SocialAssets", code: 5) }

    for frame in 0..<frameCount {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else {
            throw NSError(domain: "SocialAssets", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not allocate video frame."])
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = makeContext(width: width, height: height, buffer: CVPixelBufferGetBaseAddress(pixelBuffer), bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer))
        context.scaleBy(x: CGFloat(width) / designWidth, y: CGFloat(height) / 1920)
        if let photoCampaign {
            drawPhotoVideoFrame(context, time: Double(frame) / Double(fps), logo: logo, photos: photoCampaign, variant: variant)
        } else {
            drawVideoFrame(context, time: Double(frame) / Double(fps), logo: logo, variant: variant)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        let presentationTime = CMTime(value: Int64(frame), timescale: fps)
        guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw writer.error ?? NSError(domain: "SocialAssets", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not append video frame."])
        }
    }

    input.markAsFinished()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "SocialAssets", code: 8) }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = root.appendingPathComponent("Marketing/Social-Media", isDirectory: true)
let sourceDirectory = outputDirectory.appendingPathComponent("Quellen", isDirectory: true)
let logoURL = root.appendingPathComponent("Assets.xcassets/WertweitLogo.imageset/WertweitLogo.png")
let photoCampaignOnly = CommandLine.arguments.contains("--photo-campaign-only")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
guard let source = CGImageSourceCreateWithURL(logoURL as CFURL, nil),
      let logo = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Could not load brand logo at \(logoURL.path)")
}

if !photoCampaignOnly {
    try savePNG(output: outputDirectory.appendingPathComponent("01-feed-portrait-4x5.png"), width: 1080, height: 1350) {
        drawFeedPoster($0, logo: logo, height: $1, portrait: true)
    }
    try savePNG(output: outputDirectory.appendingPathComponent("02-feed-square.png"), width: 1080, height: 1080) {
        drawSquarePoster($0, logo: logo, height: $1)
    }
    try savePNG(output: outputDirectory.appendingPathComponent("03-story-reel-cover.png"), width: 1080, height: 1920) {
        drawStoryPoster($0, logo: logo, height: $1, travelFocus: false)
    }
    try savePNG(output: outputDirectory.appendingPathComponent("04-story-travel-cover.png"), width: 1080, height: 1920) {
        drawStoryPoster($0, logo: logo, height: $1, travelFocus: true)
    }
    try makeVideo(output: outputDirectory.appendingPathComponent("05-reel-wertweit-12s.mp4"), logo: logo, variant: 0)
    try makeVideo(output: outputDirectory.appendingPathComponent("06-reel-reiseplanung-12s.mp4"), logo: logo, variant: 1)
}

func loadPhoto(_ name: String) -> CGImage {
    let url = sourceDirectory.appendingPathComponent(name)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Could not load campaign photo at \(url.path)")
    }
    return image
}

let roadPhoto = loadPhoto("unsplash-road-through-red-rocks.jpg")
let cityPhoto = loadPhoto("unsplash-city-evening.jpg")
let hikerPhoto = loadPhoto("unsplash-alpine-hiker.jpg")
let campaignPhotos = [roadPhoto, cityPhoto, hikerPhoto]

try savePNG(output: outputDirectory.appendingPathComponent("07-story-road-photo.png"), width: 1080, height: 1920) {
    drawPhotoPoster($0, logo: logo, image: roadPhoto, height: $1, headline: ["Deine Reise.", "Dein Überblick."], detail: "Vor der Reise einfach umrechnen.", story: true)
}
try savePNG(output: outputDirectory.appendingPathComponent("08-story-city-photo.png"), width: 1080, height: 1920) {
    drawPhotoPoster($0, logo: logo, image: cityPhoto, height: $1, headline: ["Dein Geld.", "Deine Reise."], detail: "Kurse und Wechselkosten im Blick.", story: true)
}
try savePNG(output: outputDirectory.appendingPathComponent("09-feed-travel-photo-4x5.png"), width: 1080, height: 1350) {
    drawPhotoPoster($0, logo: logo, image: hikerPhoto, height: $1, headline: ["Währungen", "klar vergleichen."], detail: "Wertweit für unterwegs.", story: false)
}
try makeVideo(output: outputDirectory.appendingPathComponent("10-reel-road-photo-12s.mp4"), logo: logo, variant: 0, photoCampaign: campaignPhotos)
try makeVideo(output: outputDirectory.appendingPathComponent("11-reel-city-photo-12s.mp4"), logo: logo, variant: 1, photoCampaign: campaignPhotos)

print("Created the photo campaign assets in \(outputDirectory.path)")