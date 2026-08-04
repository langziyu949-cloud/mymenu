import 'dotenv/config';
import { DeepSeekClient } from './ai/deepSeekClient.js';
import { loadConfig } from './config.js';
import {
  buildHuaweiHandler,
  type HuaweiHttpEvent,
  type HuaweiHttpResponse
} from './huawei/buildHuaweiHandler.js';
import { RecipeService } from './services/recipeService.js';

type RuntimeHandler = (event: HuaweiHttpEvent) => Promise<HuaweiHttpResponse>;

let runtimeHandler: RuntimeHandler | undefined;

export async function handler(event: HuaweiHttpEvent): Promise<HuaweiHttpResponse> {
  if (runtimeHandler === undefined) {
    const config = loadConfig();
    const client = new DeepSeekClient(config);
    const service = new RecipeService(client);
    runtimeHandler = buildHuaweiHandler({ config, service });
  }
  return runtimeHandler(event);
}
