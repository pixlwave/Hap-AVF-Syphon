import Cocoa
import AVFoundation

class ViewController: NSViewController {
    
    var displayTimer: Timer?
    var context: NSOpenGLContext?
    
    var player: AVPlayer?
    var hapOutput = AVPlayerItemHapDXTOutput()
    var buffer: HapPixelBufferTexture!
    var size = NSSize(width: 512, height: 512)
    var textureSize = NSSize(width: 512, height: 512)
    var syphonServer: SyphonServer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        displayTimer = Timer.scheduledTimer(timeInterval: 1 / 60, target: self, selector: #selector(screenRefresh), userInfo: nil, repeats: true)
        
        let contextAttributes: [NSOpenGLPixelFormatAttribute] = [
            NSOpenGLPixelFormatAttribute(NSOpenGLPFADoubleBuffer),
            NSOpenGLPixelFormatAttribute(NSOpenGLPFAColorSize), NSOpenGLPixelFormatAttribute(32),
            NSOpenGLPixelFormatAttribute(0)
        ]
        
        context = NSOpenGLContext(format: NSOpenGLPixelFormat(attributes: contextAttributes)!, share: nil)
        context?.makeCurrentContext()
        
        syphonServer = SyphonServer(name: "Video", context: context!.cglContextObj, options: nil)
        
        buffer = HapPixelBufferTexture(context: context?.cglContextObj)
        
        hapOutput.suppressesPlayerRendering = true
        
        player = AVPlayer(url: Bundle.main.url(forResource: "video_hap", withExtension: "mov")!)
        player?.actionAtItemEnd = .none
        player?.currentItem?.add(hapOutput)
        player?.play()
    }
    
    func screenRefresh() {
        let outputTime = hapOutput.itemTime(forHostTime: CACurrentMediaTime())
        
        if let dxtFrame = hapOutput.allocFrameClosest(to: outputTime) {
            size = dxtFrame.imgSize
            buffer.decodedFrame = dxtFrame
        }
        
        if buffer.textureCount > 0 {
            textureSize.width = CGFloat(buffer.textureWidths.pointee)
            textureSize.height = CGFloat(buffer.textureHeights.pointee)
            
            syphonServer?.publishFrameTexture(buffer.textureNames[0], textureTarget: GLenum(GL_TEXTURE_2D), imageRegion: NSRect(origin: CGPoint(x: 0, y: 0), size: size), textureDimensions: textureSize, flipped: true)
        }
    }
    
    @IBAction func rewind(_ sender: AnyObject) {
        player?.seek(to: kCMTimeZero)
    }
}
