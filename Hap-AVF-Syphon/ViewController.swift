import Cocoa
import AVFoundation

class ViewController: NSViewController {
    
    var displayTimer: Timer?
    var context: NSOpenGLContext?
    
    var globalBufferPool: VVBufferPool!
    var isfScene: ISFGLScene!
    var buffer: VVBuffer?
    
    var player: AVPlayer?
    var hapOutput = AVPlayerItemHapDXTOutput()
    var size = NSSize(width: 512, height: 512)
    var textureSize = NSSize(width: 512, height: 512)
    var syphonServer: SyphonServer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        displayTimer = Timer.scheduledTimer(timeInterval: 1 / 60, target: self, selector: #selector(screenRefresh), userInfo: nil, repeats: true)
        
        context = NSOpenGLContext(format: GLScene.defaultPixelFormat(), share: nil)
        
        // create the global buffer pool from the shared context
        // and keep a reference to the global buffer pool cast as a VVBufferPool
        VVBufferPool.createGlobalVVBufferPool(withSharedContext: context)
        globalBufferPool = VVBufferPool.globalVVBufferPool() as! VVBufferPool
        
        syphonServer = SyphonServer(name: "Video", context: context!.cglContextObj, options: nil)
        
        //	load an ISF file
        isfScene = ISFGLScene(sharedContext: context)
        isfScene.useFile(Bundle.main.path(forResource: "Passthrough", ofType: "fs"))
        
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
            buffer = globalBufferPool.allocBuffer(forPlane: 0, in: dxtFrame)
        }
        
        if let buffer = buffer {
            isfScene.setFilterInputImageBuffer(buffer)
            if let output = isfScene.allocAndRender(toBufferSized: size) {
                syphonServer?.publishFrameTexture(output.name, textureTarget: output.target, imageRegion: NSRect(origin: CGPoint(x: 0, y: 0), size: size), textureDimensions: size, flipped: true)
            }
        }
    }
    
    @IBAction func rewind(_ sender: AnyObject) {
        player?.seek(to: kCMTimeZero)
    }
}
