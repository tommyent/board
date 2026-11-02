import SwiftUI
import AppKit

@main struct RenderPreviews {
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let destination = CommandLine.arguments.count > 1 ? URL(fileURLWithPath:CommandLine.arguments[1]) : root.appendingPathComponent("Assets/ThemePreviews")
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        for theme in ["Dark","Light","Glass Dark","Glass Clear"] {
            let view = KeyboardView(layout:"ANSI",held:[0,1,2,3,38],theme:theme,accent:Accent(nil)).padding(12).frame(width:600,height:252).background(theme.contains("Dark") ? Color(white:0.18) : Color(white:0.9))
            let renderer = ImageRenderer(content:view); renderer.scale = 2
            if let cg = renderer.cgImage { let rep = NSBitmapImageRep(cgImage:cg); try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(theme.replacingOccurrences(of:" ",with:"-")+".png")) }
        }
        let thumbnails = CommandLine.arguments.count > 1 ? destination.appendingPathComponent("SwitchThumbnails") : root.appendingPathComponent("Assets/SwitchThumbnails")
        try FileManager.default.createDirectory(at:thumbnails,withIntermediateDirectories:true)
        for profile in SoundProfile.catalog {
            let renderer = ImageRenderer(content:SwitchMark(color:Color(hex:profile.color)).padding(4)); renderer.scale = 4
            if let cg = renderer.cgImage { let rep = NSBitmapImageRep(cgImage:cg); try rep.representation(using:.png,properties:[:])!.write(to:thumbnails.appendingPathComponent(profile.id+".png")) }
        }
        let app = AppState(defaults:UserDefaults(suiteName:"com.tommyent.Board.asset-render")!)
        app.settings = AppSettings()
        for key in [1,40,49] { app.visualTrail.press(.init(key:key,transition:.press,modifiers:0,timestamp:ProcessInfo.processInfo.systemUptime)) }
        for _ in 0..<42 { _ = app.combo.press(at:0,settings:app.settings.visualizer) }
        for theme in ["Monochrome","Amber","Neon"] {
            app.settings.visualizer.style = "Combo"; app.settings.visualizer.comboTheme = theme
            let renderer = ImageRenderer(content:OverlayContent(app:app).frame(width:210,height:170)); renderer.scale = 2
            if let cg = renderer.cgImage { let rep = NSBitmapImageRep(cgImage:cg); try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent("Combo-"+theme+".png")) }
        }
        if CommandLine.arguments.count > 1 {
            let keys = [0,1,2,3,4,5,6,7,8,9,11,12,13,14,15]
            for profile in SoundProfile.catalog {
                app.settings.sound.profile = profile.id
                for (name,style,flow,motion) in [("Keyboard","Keyboard","Row","Pop"),("Ribbon","Keystrokes","Row","Slide"),("Column","Keystrokes","Column","Pop"),("Float","Keystrokes","Row","Float"),("Combo","Combo","Row","Pulse"),("Bezel","Bezel","Row","Pop")] {
                    app.settings.visualizer.style = style; app.settings.visualizer.flow = flow; app.settings.visualizer.motion = motion
                    app.visualTrail = VisualizerTrail()
                    let now = ProcessInfo.processInfo.systemUptime
                    for (index,key) in keys.enumerated() {
                        let time = now-Double(keys.count-1-index)*0.075
                        app.visualTrail.press(.init(key:key,transition:.press,modifiers:0,timestamp:time))
                        app.visualTrail.release(key,at:time+0.045)
                    }
                    app.heldKeys = [15]
                    let size = style == "Bezel" ? CGSize(width:840,height:480) : app.settings.visualizer.panelSize
                    do {
                        let renderer = ImageRenderer(content:OverlayContent(app:app).frame(width:size.width,height:size.height).background(Color(white:0.08)))
                        renderer.scale = 2
                        guard let cg = renderer.cgImage else { throw NSError(domain:"Board.Render",code:1) }
                        let rep = NSBitmapImageRep(cgImage:cg)
                        try rep.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent("\(profile.id)-\(name).png"))
                    }
                }
            }
            for (name,floating,reduced) in [("Ribbon",false,false),("Float",true,false),("Reduced",true,true)] {
                let stroke = KeystrokeVisual(key:51,chord:"⌫",count:3,time:0)
                let view = HStack(spacing:16) {
                    ForEach([0.0,0.3,0.65,0.95],id:\.self) { age in
                        VStack {
                            KeystrokeCap(stroke:stroke,color:"E5A4B1",progress:age,float:floating,reduceMotion:reduced,light:false).frame(width:90,height:210,alignment:.bottom)
                            Text(String(format:"%.2f s",age*VisualizerTrail.lifetime)).foregroundStyle(.white)
                        }
                    }
                }.padding(20).background(Color(white:0.08))
                let renderer = ImageRenderer(content:view); renderer.scale = 2
                guard let cg = renderer.cgImage else { throw NSError(domain:"Board.Render",code:2) }
                try NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent("\(name)-ages.png"))
            }
        }
        print("Rendered previews to \(destination.path)")
    }
}
