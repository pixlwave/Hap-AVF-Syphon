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
    var emptyFrame: HapDecoderFrame?
    var bufferArray: [VVBuffer]?
    var dxtFrame: HapDecoderFrame?
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
        
        //  make the "alloc frame" block: this takes a CMSampleBufferRef and returns a HapDecoderFrame that has been configured and is ready to be decompressed into
        hapOutput.setAllocFrameBlock { (decompressMe) -> HapDecoderFrame? in
            //  make an empty decoder frame from the buffer (the basic fields describing the data properties of the DXT frame are populated, but no memory is allocated to decompress the DXT into)
            if let emptyFrame = HapDecoderFrame(emptyWithHapSampleBuffer: decompressMe),
                //  make a CPU-backed/tex range VVBuffer for each plane in the decoder frame
                let bufferArray = self.globalBufferPool.createBuffers(for: emptyFrame) as? [VVBuffer] {
                //  populate the hap decoder frame i'll be returning with the CPU-based memory from the buffers, and ensure that the decoder will retain the buffers (this has to be done for each plane in the frame)
                for (i, buffer) in bufferArray.enumerated() {
                    emptyFrame.dxtDatas[i] = buffer.cpuBackingPtr()
                    emptyFrame.dxtDataSizes[i] = Int(VVBufferDescriptorCalculateCPUBackingForSize(buffer.descriptorPtr(), buffer.backingSize))
                }
                //  add the array of buffers to the frame's userInfo- we want the frame to retain the array of buffers...
                emptyFrame.userInfo = bufferArray
                self.emptyFrame = emptyFrame
                return emptyFrame
            }
            return nil
        }
        
        //  make the post-decode frame block: tell the buffers from the decoded frame that their backing has been updated
        hapOutput.setPostDecode { (decodedFrame) in
            if let buffers = decodedFrame?.userInfo as? [VVBuffer] {
                print("Number of bufs: \(buffers.count)")
                for buffer in buffers {
                    VVBufferPool.pushTexRangeBufferRAMtoVRAM(buffer, usingContext: self.context?.cglContextObj)
                }
                //  ...at this point, the VVBuffer instances in "buffers" have the images that you want to work with- do whatever you want with 'em!
                self.bufferArray = buffers
            }
        }
        
        player = AVPlayer(url: Bundle.main.url(forResource: "video_hap", withExtension: "mov")!)
        player?.actionAtItemEnd = .none
        player?.currentItem?.add(hapOutput)
        player?.play()
    }
    
    func screenRefresh() {
        let outputTime = hapOutput.itemTime(forHostTime: CACurrentMediaTime())
        dxtFrame = hapOutput.allocFrame(for: outputTime)
        if let buffer = bufferArray?.first {
            isfScene.setFilterInputImageBuffer(buffer)
            if let isfOutput = isfScene.allocAndRender(toBufferSized: size) {
                syphonServer?.publishFrameTexture(isfOutput.name, textureTarget: isfOutput.target, imageRegion: NSRect(origin: CGPoint(x: 0, y: 0), size: size), textureDimensions: size, flipped: isfOutput.flipped)
            }
        }
        
        globalBufferPool.housekeeping()
    }
    
    @IBAction func rewind(_ sender: AnyObject) {
        player?.seek(to: kCMTimeZero)
    }
}
