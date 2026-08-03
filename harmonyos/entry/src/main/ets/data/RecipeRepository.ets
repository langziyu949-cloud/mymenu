import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { RecipeDatabase } from './RecipeDatabase';
import { DraftRecipeVersion, DraftSession, RecipeDraft, RecipeRecord } from '../models/RecipeModels';

export class RecipeRepository {
  private readonly store: relationalStore.RdbStore;

  private constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  static async create(context: common.UIAbilityContext): Promise<RecipeRepository> {
    const store: relationalStore.RdbStore = await RecipeDatabase.open(context);
    return new RecipeRepository(store);
  }

  async save(draft: RecipeDraft): Promise<RecipeRecord> {
    const recipe: RecipeRecord = {
      id: util.generateRandomUUID(true),
      name: draft.name.trim(),
      steps: draft.steps,
      ingredients: draft.ingredients,
      seasonings: draft.seasonings,
      experience: draft.experience,
      photoPath: draft.photoPath,
      originalText: draft.originalText,
      createdAt: Date.now(),
      updatedAt: Date.now()
    };

    const values: relationalStore.ValuesBucket = {
      id: recipe.id,
      name: recipe.name,
      steps_json: JSON.stringify(recipe.steps),
      ingredients_json: JSON.stringify(recipe.ingredients),
      seasonings_json: JSON.stringify(recipe.seasonings),
      experience_json: JSON.stringify(recipe.experience),
      photo_path: recipe.photoPath,
      original_text: recipe.originalText,
      created_at: recipe.createdAt,
      updated_at: recipe.updatedAt
    };
    await this.store.insert('recipes', values);
    return recipe;
  }

  async listNewestFirst(): Promise<RecipeRecord[]> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('recipes');
    predicates.isNull('deleted_at');
    predicates.orderByDesc('created_at');
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates);
    const recipes: RecipeRecord[] = [];

    try {
      while (resultSet.goToNextRow()) {
        recipes.push({
          id: resultSet.getString(resultSet.getColumnIndex('id')),
          name: resultSet.getString(resultSet.getColumnIndex('name')),
          steps: JSON.parse(resultSet.getString(resultSet.getColumnIndex('steps_json'))) as string[],
          ingredients: JSON.parse(resultSet.getString(resultSet.getColumnIndex('ingredients_json'))) as string[],
          seasonings: JSON.parse(resultSet.getString(resultSet.getColumnIndex('seasonings_json'))) as string[],
          experience: JSON.parse(resultSet.getString(resultSet.getColumnIndex('experience_json'))) as string[],
          photoPath: resultSet.getString(resultSet.getColumnIndex('photo_path')),
          originalText: resultSet.getString(resultSet.getColumnIndex('original_text')),
          createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
          updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
        });
      }
    } finally {
      resultSet.close();
    }
    return recipes;
  }

  async search(query: string): Promise<RecipeRecord[]> {
    const normalized: string = query.trim().toLocaleLowerCase();
    const recipes: RecipeRecord[] = await this.listNewestFirst();
    if (normalized.length === 0) {
      return recipes;
    }
    return recipes.filter((recipe: RecipeRecord) =>
      recipe.name.toLocaleLowerCase().includes(normalized) ||
      recipe.ingredients.join(' ').toLocaleLowerCase().includes(normalized) ||
      recipe.seasonings.join(' ').toLocaleLowerCase().includes(normalized));
  }

  async update(recipe: RecipeRecord): Promise<void> {
    const values: relationalStore.ValuesBucket = {
      name: recipe.name.trim(),
      steps_json: JSON.stringify(recipe.steps),
      ingredients_json: JSON.stringify(recipe.ingredients),
      seasonings_json: JSON.stringify(recipe.seasonings),
      experience_json: JSON.stringify(recipe.experience),
      photo_path: recipe.photoPath,
      updated_at: Date.now()
    };
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('recipes');
    predicates.equalTo('id', recipe.id);
    await this.store.update(values, predicates);
  }

  async softDelete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('recipes');
    predicates.equalTo('id', id);
    await this.store.update({ deleted_at: Date.now() }, predicates);
  }

  async restore(id: string): Promise<void> {
    await this.store.executeSql('UPDATE recipes SET deleted_at = NULL WHERE id = ?', [id]);
  }

  async hardDelete(id: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('recipes');
    predicates.equalTo('id', id);
    await this.store.delete(predicates);
  }

  async saveDraft(draft: DraftSession): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('draft_sessions');
    predicates.equalTo('id', 'active');
    await this.store.delete(predicates);
    await this.store.insert('draft_sessions', {
      id: 'active',
      original_text: draft.originalText,
      question_text: draft.questionText,
      question_ids_json: JSON.stringify(draft.questionIds),
      recipe_name: draft.recipeName,
      steps_json: JSON.stringify(draft.steps),
      ingredients_json: JSON.stringify(draft.ingredients),
      seasonings_json: JSON.stringify(draft.seasonings),
      experience_json: JSON.stringify(draft.experience),
      last_instruction: draft.lastInstruction,
      assistant_reply: draft.assistantReply,
      history_json: JSON.stringify(draft.history),
      updated_at: draft.updatedAt
    });
  }

  async loadDraft(): Promise<DraftSession | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('draft_sessions');
    predicates.equalTo('id', 'active');
    const resultSet: relationalStore.ResultSet = await this.store.query(predicates);
    try {
      if (!resultSet.goToNextRow()) {
        return null;
      }
      return {
        originalText: resultSet.getString(resultSet.getColumnIndex('original_text')),
        questionText: resultSet.getString(resultSet.getColumnIndex('question_text')),
        questionIds: JSON.parse(
          resultSet.getString(resultSet.getColumnIndex('question_ids_json'))) as string[],
        recipeName: resultSet.getString(resultSet.getColumnIndex('recipe_name')),
        steps: JSON.parse(resultSet.getString(resultSet.getColumnIndex('steps_json'))) as string[],
        ingredients: JSON.parse(resultSet.getString(resultSet.getColumnIndex('ingredients_json'))) as string[],
        seasonings: JSON.parse(resultSet.getString(resultSet.getColumnIndex('seasonings_json'))) as string[],
        experience: JSON.parse(resultSet.getString(resultSet.getColumnIndex('experience_json'))) as string[],
        lastInstruction: resultSet.getString(resultSet.getColumnIndex('last_instruction')),
        assistantReply: resultSet.getString(resultSet.getColumnIndex('assistant_reply')),
        history: JSON.parse(
          resultSet.getString(resultSet.getColumnIndex('history_json'))) as DraftRecipeVersion[],
        updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
      };
    } finally {
      resultSet.close();
    }
  }

  async clearDraft(): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('draft_sessions');
    predicates.equalTo('id', 'active');
    await this.store.delete(predicates);
  }
}
