import Cocoa
import AVFoundation

class ViewController: NSViewController {
    
    var displayTimer: Timer?
    var context: NSOpenGLContext?
    
    var globalBufferPool: VVBufferPool!
    var isfScene: ISFGLScene!
    
    var player: AVPlayer?
    var hapOutput = AVPlayerItemHapDXTOutput()
    var lastRenderedBuffer: VVBuffer?
    var size = NSSize(width: 640, height: 360)
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
        
        //	make the decoder frame alocator block: i want to create a frame that will decode into a texture range- RAM that is mapped directly to VRAM and uploads via DMA
        hapOutput.setAllocFrameBlock { decompressMe -> HapDecoderFrame? in
            guard let decompressMe = decompressMe else { return nil }
            
            //	make an empty decoder frame from the buffer (the basic fields describing the data properties of the DXT frame are populated, but no memory is allocated to decompress the DXT into)
            guard let emptyFrame = HapDecoderFrame(emptyWithHapSampleBuffer: decompressMe) else { return nil }
                
            //	make a CPU-backed/tex range VVBuffers for each plane in the decoder frame
            guard let bufferArray = self.globalBufferPool.createBuffers(for: emptyFrame) as? [VVBuffer] else { return nil }
            
            //	populate the hap decoder frame i'll be returning with the CPU-based memory from the buffer, and ensure that the decoder will retain the buffers (this has to be done for each plane in the frame)
            for (i, buffer) in bufferArray.enumerated() {
                emptyFrame.dxtDatas[i] = buffer.cpuBackingPtr()
                emptyFrame.dxtDataSizes[i] = Int(VVBufferDescriptorCalculateCPUBackingForSize(buffer.descriptorPtr(), buffer.backingSize))
            }
            
            //	add the array of buffers to the frame's userInfo- we want the frame to retain the array of buffers...
            emptyFrame.userInfo = bufferArray
            
            return emptyFrame
        }
        
        //	make the post decode block: after decoding, i want to upload the DXT data to a GL texture via DMA, on the decode thread
        hapOutput.setPostDecode { [weak self] decodedFrame in
                self?.finishDecodingHapFrame(decodedFrame)
        }
        
        player = AVPlayer(url: Bundle.main.url(forResource: "video_hap", withExtension: "mov")!)
        player?.actionAtItemEnd = .none
        player?.currentItem?.add(hapOutput)
        player?.play()
    }
    
    func screenRefresh() {
        objc_sync_enter(self)       // closest to objc @synchronised self?
            let frameTime = hapOutput.itemTime(forMachAbsoluteTime: Int64(mach_absolute_time()))
            let dxtFrame = hapOutput.allocFrameClosest(to: frameTime)
        
            if let frameBuffers = dxtFrame?.userInfo as? [VVBuffer], let buffer = frameBuffers.first {
                
                isfScene.setFilterInputImageBuffer(buffer)      // just a placeholder for swizzle scenes
                
                if let isfOutput = isfScene.allocAndRender(toBufferSized: size) {
                    syphonServer?.publishFrameTexture(isfOutput.name, textureTarget: isfOutput.target, imageRegion: isfOutput.srcRect, textureDimensions: isfOutput.size, flipped: isfOutput.flipped)
                    lastRenderedBuffer = isfOutput
                }
            }
        objc_sync_exit(self)
        
        globalBufferPool.housekeeping()
    }
    
    func finishDecodingHapFrame(_ decodedFrame: HapDecoderFrame?) {
        //	this method is called from a dispatch queue owned by the AVPlayerItemHapDXTOutput- this is important, because of the operating's restrictions on running GL contexts: a GL context may be used only by one thread at a time.  since this method will potentially be called simultaneously from multiple threads, we need to synchronized access to the GL context that this method uses to upload texture data.  we're doing this with a simple @synchronized here, but a pool of contexts would also be effective.
        if let newBuffers = decodedFrame?.userInfo as? [VVBuffer] {
            objc_sync_enter(self)       // closest to objc @synchronised self?
                for newBuffer in newBuffers {
                    VVBufferPool.pushTexRangeBufferRAMtoVRAM(newBuffer, usingContext: context?.cglContextObj)
                }
            objc_sync_exit(self)
        }
    }
    
    @IBAction func rewind(_ sender: AnyObject) {
        player?.seek(to: kCMTimeZero)
    }
}
