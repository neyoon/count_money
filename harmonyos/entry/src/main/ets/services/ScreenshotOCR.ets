import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

export class ScreenshotOCR {
  static async pick(): Promise<string> {
    const view = new photoAccessHelper.PhotoViewPicker();
    const result = await view.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1 });
    if (result.photoUris.length === 0) return '';
    return ScreenshotOCR.recognize(result.photoUris[0]);
  }

  static async recognize(uri: string): Promise<string> {
    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) throw new Error('此设备暂不支持系统 OCR，可使用手动记账或拖入文字');
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    let source: image.ImageSource | undefined = undefined;
    let pixels: image.PixelMap | undefined = undefined;
    let initialized = false;
    try {
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const scale = Math.min(1, 2560 / Math.max(info.size.width, info.size.height));
      pixels = await source.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: { width: Math.max(1, Math.round(info.size.width * scale)), height: Math.max(1, Math.round(info.size.height * scale)) }
      });
      initialized = await textRecognition.init();
      if (!initialized) throw new Error('系统 OCR 初始化失败，请使用手动记账');
      const result = await textRecognition.recognizeText({ pixelMap: pixels });
      return result.value;
    } finally {
      // Cleanup each resource independently even if a prior release fails.
      if (pixels) await pixels.release().catch(() => {});
      if (source) await source.release().catch(() => {});
      fileIo.closeSync(file);
      if (initialized) await textRecognition.release().catch(() => {});
    }
  }
}
