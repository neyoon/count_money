import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export class BackupFiles {
  static async read(): Promise<string> {
    const view = new picker.DocumentViewPicker();
    const uris = await view.select({ maxSelectNumber: 1 });
    if (uris.length === 0) return '';
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_ONLY);
    try {
      const size = fileIo.statSync(file.fd).size;
      if (size > 20 * 1024 * 1024) throw new Error('备份超过 20 MB');
      const buffer = new ArrayBuffer(size);
      let offset = 0;
      while (offset < size) {
        const chunk = new ArrayBuffer(size - offset);
        const count = fileIo.readSync(file.fd, chunk);
        if (count <= 0) throw new Error('备份文件未完整读取');
        new Uint8Array(buffer).set(new Uint8Array(chunk, 0, count), offset);
        offset += count;
      }
      return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
    } finally { fileIo.closeSync(file); }
  }

  static async write(contents: string): Promise<boolean> {
    const view = new picker.DocumentViewPicker();
    const day = new Date().toISOString().slice(0, 10);
    const uris = await view.save({ newFileNames: [`count-money-${day}.json`] });
    if (uris.length === 0) return false;
    const file = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      const bytes = new util.TextEncoder().encodeInto(contents);
      let offset = 0;
      while (offset < bytes.length) {
        const remaining = bytes.slice(offset);
        const count = fileIo.writeSync(file.fd, remaining.buffer);
        if (count <= 0) throw new Error('备份未完整写入');
        offset += count;
      }
      fileIo.fsyncSync(file.fd);
      return true;
    } finally { fileIo.closeSync(file); }
  }
}
