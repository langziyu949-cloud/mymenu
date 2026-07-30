import 'dotenv/config';
import { DeepSeekClient } from './ai/deepSeekClient.js';
import { loadConfig } from './config.js';
import { buildServer } from './http/buildServer.js';
import { RecipeService } from './services/recipeService.js';

const config = loadConfig();
const client = new DeepSeekClient(config);
const service = new RecipeService(client);
const server = buildServer({ config, service });

await server.listen({ host: '0.0.0.0', port: config.PORT });
