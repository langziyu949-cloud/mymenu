import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

function photoExtension(uri: string): string {
  const normalized: string = uri.toLowerCase().split('?')[0];
  const extensions: string[] = ['.jpeg', '.jpg', '.png', '.webp', '.heic', '.heif', '.gif', '.bmp'];
  for (const extension of extensions) {
    if (normalized.endsWith(extension)) {
      return extension;
    }
  }
  return '.jpg';
}

export async function pickRecipePhotoUri(allowCamera: boolean): Promise<string> {
  const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
  const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = 1;
  options.isPhotoTakingSupported = allowCamera;
  const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
  if (result.photoUris.length === 0) {
    return '';
  }
  return result.photoUris[0];
}

export async function persistRecipePhoto(
  context: common.UIAbilityContext,
  sourceUri: string
): Promise<string> {
  const destinationPath: string =
    `${context.filesDir}/recipe-cover-${Date.now()}${photoExtension(sourceUri)}`;
  let sourceFile: fs.File | null = null;
  let destinationFile: fs.File | null = null;
  try {
    sourceFile = fs.openSync(sourceUri, fs.OpenMode.READ_ONLY);
    destinationFile = fs.openSync(
      destinationPath,
      fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
    );
    await fs.copyFile(sourceFile.fd, destinationFile.fd);
    return `file://${destinationPath}`;
  } finally {
    if (destinationFile !== null) {
      fs.closeSync(destinationFile.fd);
    }
    if (sourceFile !== null) {
      fs.closeSync(sourceFile.fd);
    }
  }
}
