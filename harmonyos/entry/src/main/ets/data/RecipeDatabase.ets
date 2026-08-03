import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const DATABASE_NAME: string = 'kitchen_master.db';
const CREATE_RECIPES_TABLE: string =
  'CREATE TABLE IF NOT EXISTS recipes (' +
    'id TEXT PRIMARY KEY, ' +
    'name TEXT NOT NULL, ' +
    'steps_json TEXT NOT NULL, ' +
    'ingredients_json TEXT NOT NULL, ' +
    'seasonings_json TEXT NOT NULL, ' +
    'experience_json TEXT NOT NULL, ' +
    'photo_path TEXT NOT NULL DEFAULT \'\', ' +
    'original_text TEXT NOT NULL DEFAULT \'\', ' +
    'created_at INTEGER NOT NULL, ' +
    'updated_at INTEGER NOT NULL DEFAULT 0, ' +
    'deleted_at INTEGER' +
  ')';

const CREATE_DRAFT_TABLE: string =
  'CREATE TABLE IF NOT EXISTS draft_sessions (' +
    'id TEXT PRIMARY KEY, ' +
    'original_text TEXT NOT NULL, ' +
    'recipe_name TEXT NOT NULL, ' +
    'steps_json TEXT NOT NULL, ' +
    'ingredients_json TEXT NOT NULL, ' +
    'seasonings_json TEXT NOT NULL, ' +
    'experience_json TEXT NOT NULL, ' +
    'last_instruction TEXT NOT NULL, ' +
    'assistant_reply TEXT NOT NULL DEFAULT \'\', ' +
    'history_json TEXT NOT NULL DEFAULT \'[]\', ' +
    'updated_at INTEGER NOT NULL' +
  ')';

const RECIPE_MIGRATIONS: string[] = [
  'ALTER TABLE recipes ADD COLUMN photo_path TEXT NOT NULL DEFAULT \'\'',
  'ALTER TABLE recipes ADD COLUMN original_text TEXT NOT NULL DEFAULT \'\'',
  'ALTER TABLE recipes ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE recipes ADD COLUMN deleted_at INTEGER'
];

const DRAFT_MIGRATIONS: string[] = [
  'ALTER TABLE draft_sessions ADD COLUMN assistant_reply TEXT NOT NULL DEFAULT \'\'',
  'ALTER TABLE draft_sessions ADD COLUMN history_json TEXT NOT NULL DEFAULT \'[]\''
];

export class RecipeDatabase {
  private static store: relationalStore.RdbStore | null = null;

  static async open(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    if (RecipeDatabase.store !== null) {
      return RecipeDatabase.store;
    }

    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    await store.executeSql(CREATE_RECIPES_TABLE);
    for (const migration of RECIPE_MIGRATIONS) {
      try {
        await store.executeSql(migration);
      } catch {
      }
    }
    await store.executeSql('UPDATE recipes SET updated_at = created_at WHERE updated_at = 0');
    await store.executeSql(CREATE_DRAFT_TABLE);
    for (const migration of DRAFT_MIGRATIONS) {
      try {
        await store.executeSql(migration);
      } catch {
      }
    }
    RecipeDatabase.store = store;
    return store;
  }
}
