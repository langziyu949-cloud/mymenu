import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

export async function pickRecipePhoto(context: common.UIAbilityContext, allowCamera: boolean): Promise<string> {
  const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
  const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = 1;
  options.isPhotoTakingSupported = allowCamera;
  const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
  if (result.photoUris.length === 0) {
    return '';
  }
  const destination: string = `${context.filesDir}/recipe-cover-${Date.now()}.img`;
  await fs.copyFile(result.photoUris[0], destination);
  return `file://${destination}`;
}
