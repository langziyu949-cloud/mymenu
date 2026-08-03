import { common } from '@kit.AbilityKit';
import { DemoRecipeDraft, DemoRevisionResult, generateDemoRecipe, reviseDemoRecipe } from '../domain/DemoRecipeGenerator';
import { RecipeRepository } from '../data/RecipeRepository';
import { DraftSession, RecipeDraft, RecipeRecord } from '../models/RecipeModels';
import { pickRecipePhoto } from '../services/PhotoPickerService';

const PAPER: string = '#F2F5F1';
const CARD: string = '#FCFDFB';
const INK: string = '#17231F';
const JADE: string = '#173F34';
const JADE_SOFT: string = '#DCE8E1';
const CHILI: string = '#D95D42';
const MUTED: string = '#707A75';
const LINE: string = '#DDE3DF';
const ESTIMATE: string = '#FFF0D8';
const ESTIMATE_TEXT: string = '#8A5B13';

@Entry
@Component
struct Index {
  @State currentPage: number = 1;
  @State composerText: string = '';
  @State originalText: string = '';
  @State hasDraft: boolean = false;
  @State hasQuestion: boolean = false;
  @State questionText: string = '';
  @State latestInstruction: string = '';
  @State assistantReply: string = '';
  @State draftName: string = '';
  @State draftSteps: string[] = [];
  @State draftIngredients: string[] = [];
  @State draftSeasonings: string[] = [];
  @State draftExperience: string[] = [];
  @State statusMessage: string = '';
  @State isWorking: boolean = false;

  @State recipes: RecipeRecord[] = [];
  @State visibleRecipes: RecipeRecord[] = [];
  @State searchText: string = '';
  @State highlightedRecipeId: string = '';

  @State detailId: string = '';
  @State detailName: string = '';
  @State detailSteps: string[] = [];
  @State detailIngredients: string[] = [];
  @State detailSeasonings: string[] = [];
  @State detailExperience: string[] = [];
  @State detailPhotoPath: string = '';
  @State detailOriginalText: string = '';
  @State detailCreatedAt: number = 0;
  @State detailUpdatedAt: number = 0;
  @State isEditingDetail: boolean = false;
  @State editName: string = '';
  @State editSteps: string = '';
  @State editIngredients: string = '';
  @State editSeasonings: string = '';
  @State editExperience: string = '';

  @State showPhotoPrompt: boolean = false;
  @State showDeleteConfirm: boolean = false;
  @State showDiscardConfirm: boolean = false;
  @State archiveAnimating: boolean = false;
  @State archiveName: string = '';
  @State archiveScale: number = 1;
  @State archiveX: number = 0;
  @State archiveY: number = 0;
  @State archiveOpacity: number = 1;
  @State undoVisible: boolean = false;
  @State pendingDeletedId: string = '';
  @State pendingDeletedName: string = '';

  private repository: RecipeRepository | null = null;

  aboutToAppear(): void {
    this.initialize();
  }

  private async initialize(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      this.repository = await RecipeRepository.create(context);
      await this.refreshRecipes();
      await this.restoreDraft();
    } catch {
      this.statusMessage = '本地菜谱夹初始化失败，请重新打开应用';
    }
  }

  private async refreshRecipes(): Promise<void> {
    if (this.repository === null) {
      return;
    }
    this.recipes = await this.repository.listNewestFirst();
    this.visibleRecipes = this.searchText.trim().length > 0 ?
      await this.repository.search(this.searchText) : this.recipes;
  }

  private async restoreDraft(): Promise<void> {
    if (this.repository === null) {
      return;
    }
    const draft: DraftSession | null = await this.repository.loadDraft();
    if (draft === null) {
      return;
    }
    if (draft.recipeName.length === 0) {
      this.composerText = draft.originalText;
      return;
    }
    this.originalText = draft.originalText;
    this.draftName = draft.recipeName;
    this.draftSteps = draft.steps;
    this.draftIngredients = draft.ingredients;
    this.draftSeasonings = draft.seasonings;
    this.draftExperience = draft.experience;
    this.latestInstruction = draft.lastInstruction;
    this.assistantReply = '未完成的菜谱已经恢复，可以继续告诉我怎么改。';
    this.hasDraft = true;
  }

  private async persistDraft(): Promise<void> {
    if (this.repository === null) {
      return;
    }
    const draft: DraftSession = {
      originalText: this.hasDraft || this.hasQuestion ? this.originalText : this.composerText,
      recipeName: this.hasDraft ? this.draftName : '',
      steps: this.hasDraft ? this.draftSteps : [],
      ingredients: this.hasDraft ? this.draftIngredients : [],
      seasonings: this.hasDraft ? this.draftSeasonings : [],
      experience: this.hasDraft ? this.draftExperience : [],
      lastInstruction: this.latestInstruction,
      updatedAt: Date.now()
    };
    await this.repository.saveDraft(draft);
  }

  private applyGeneratedRecipe(recipe: DemoRecipeDraft): void {
    this.draftName = recipe.name;
    this.draftSteps = recipe.steps;
    this.draftIngredients = recipe.ingredients;
    this.draftSeasonings = recipe.seasonings;
    this.draftExperience = recipe.experience;
    this.hasDraft = true;
    this.hasQuestion = false;
    this.questionText = '';
  }

  private shouldAskForDetails(text: string): boolean {
    const hasAction: boolean = text.includes('炒') || text.includes('煮') || text.includes('蒸') ||
      text.includes('炖') || text.includes('煎') || text.includes('烤') || text.includes('拌') ||
      text.includes('放') || text.includes('加入');
    return text.length < 8 || !hasAction;
  }

  private async sendMessage(): Promise<void> {
    const message: string = this.composerText.trim();
    if (message.length === 0 || this.isWorking) {
      this.statusMessage = '先说说这道菜是怎么做的';
      return;
    }
    this.isWorking = true;
    this.statusMessage = '';

    try {
      if (!this.hasDraft && !this.hasQuestion) {
        this.originalText = message;
        this.composerText = '';
        if (this.shouldAskForDetails(message)) {
          this.hasQuestion = true;
          this.questionText = '我还缺两个关键信息：这道菜叫什么？主要按什么顺序做？';
          await this.persistDraft();
          return;
        }
        this.applyGeneratedRecipe(generateDemoRecipe(message));
        this.assistantReply = '我按你的描述整理好了。推测的用量已经标出，你可以继续用一句话修改。';
        await this.persistDraft();
        return;
      }

      if (this.hasQuestion && !this.hasDraft) {
        this.originalText = `${this.originalText}。${message}`;
        this.composerText = '';
        this.applyGeneratedRecipe(generateDemoRecipe(this.originalText));
        this.assistantReply = '信息够了，我整理成卡片了。保存前还可以继续修改。';
        await this.persistDraft();
        return;
      }

      const current: DemoRecipeDraft = {
        name: this.draftName,
        steps: this.draftSteps,
        ingredients: this.draftIngredients,
        seasonings: this.draftSeasonings,
        experience: this.draftExperience
      };
      const revision: DemoRevisionResult = reviseDemoRecipe(current, message);
      this.latestInstruction = message;
      this.assistantReply = revision.reply;
      this.composerText = '';
      if (revision.changed) {
        this.applyGeneratedRecipe(revision.recipe);
      }
      await this.persistDraft();
    } catch {
      this.statusMessage = '这次没有整理成功，原内容已经保留，可以重试';
    } finally {
      this.isWorking = false;
    }
  }

  private canFinishDraft(): boolean {
    return this.draftName.trim().length > 0 && this.draftSteps.length > 0;
  }

  private finishDraft(): void {
    if (!this.canFinishDraft()) {
      this.statusMessage = '菜名和制作步骤还不完整';
      return;
    }
    this.showPhotoPrompt = true;
  }

  private async pickPhotoAndArchive(allowCamera: boolean): Promise<void> {
    this.showPhotoPrompt = false;
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const photoPath: string = await pickRecipePhoto(context, allowCamera);
      if (photoPath.length === 0) {
        this.showPhotoPrompt = true;
        return;
      }
      await this.archiveDraft(photoPath);
    } catch {
      this.statusMessage = '没有选中照片，菜谱还没有保存';
      this.showPhotoPrompt = true;
    }
  }

  private async archiveDraft(photoPath: string): Promise<void> {
    if (this.repository === null || !this.canFinishDraft()) {
      this.statusMessage = '菜谱夹还没有准备好';
      return;
    }
    this.isWorking = true;
    try {
      const draft: RecipeDraft = {
        name: this.draftName.trim(),
        steps: this.draftSteps,
        ingredients: this.draftIngredients,
        seasonings: this.draftSeasonings,
        experience: this.draftExperience,
        photoPath,
        originalText: this.originalText
      };
      const saved: RecipeRecord = await this.repository.save(draft);
      await this.repository.clearDraft();
      await this.refreshRecipes();
      this.showPhotoPrompt = false;
      this.archiveName = saved.name;
      this.highlightedRecipeId = saved.id;
      this.playArchiveAnimation(saved.id);
    } catch {
      this.statusMessage = '保存失败，菜谱草稿仍然保留';
    } finally {
      this.isWorking = false;
    }
  }

  private playArchiveAnimation(recipeId: string): void {
    this.archiveAnimating = true;
    this.archiveScale = 1;
    this.archiveX = 0;
    this.archiveY = 0;
    this.archiveOpacity = 1;
    animateTo({
      duration: 860,
      curve: Curve.EaseInOut,
      onFinish: () => {
        this.archiveAnimating = false;
        this.clearConversationState();
        this.currentPage = 0;
        setTimeout(() => {
          if (this.highlightedRecipeId === recipeId) {
            this.highlightedRecipeId = '';
          }
        }, 1400);
      }
    }, () => {
      this.archiveScale = 0.08;
      this.archiveX = -165;
      this.archiveY = 410;
      this.archiveOpacity = 0.18;
    });
  }

  private clearConversationState(): void {
    this.composerText = '';
    this.originalText = '';
    this.hasDraft = false;
    this.hasQuestion = false;
    this.questionText = '';
    this.latestInstruction = '';
    this.assistantReply = '';
    this.draftName = '';
    this.draftSteps = [];
    this.draftIngredients = [];
    this.draftSeasonings = [];
    this.draftExperience = [];
    this.statusMessage = '';
  }

  private async discardDraft(): Promise<void> {
    if (this.repository !== null) {
      await this.repository.clearDraft();
    }
    this.showDiscardConfirm = false;
    this.clearConversationState();
  }

  private async searchRecipes(value: string): Promise<void> {
    this.searchText = value;
    if (this.repository === null) {
      return;
    }
    this.visibleRecipes = await this.repository.search(value);
  }

  private openRecipe(recipe: RecipeRecord): void {
    this.detailId = recipe.id;
    this.detailName = recipe.name;
    this.detailSteps = recipe.steps;
    this.detailIngredients = recipe.ingredients;
    this.detailSeasonings = recipe.seasonings;
    this.detailExperience = recipe.experience;
    this.detailPhotoPath = recipe.photoPath;
    this.detailOriginalText = recipe.originalText;
    this.detailCreatedAt = recipe.createdAt;
    this.detailUpdatedAt = recipe.updatedAt;
    this.isEditingDetail = false;
    this.statusMessage = '';
  }

  private closeDetail(): void {
    this.detailId = '';
    this.isEditingDetail = false;
  }

  private beginDetailEdit(): void {
    this.editName = this.detailName;
    this.editSteps = this.detailSteps.join('\n');
    this.editIngredients = this.detailIngredients.join('\n');
    this.editSeasonings = this.detailSeasonings.join('\n');
    this.editExperience = this.detailExperience.join('\n');
    this.isEditingDetail = true;
    this.statusMessage = '';
  }

  private lines(value: string): string[] {
    return value.split('\n').map((line: string) => line.trim()).filter((line: string) => line.length > 0);
  }

  private async saveDetailChanges(): Promise<void> {
    if (this.repository === null || this.editName.trim().length === 0 || this.lines(this.editSteps).length === 0) {
      this.statusMessage = '菜名和制作步骤不能为空';
      return;
    }
    const updated: RecipeRecord = {
      id: this.detailId,
      name: this.editName.trim(),
      steps: this.lines(this.editSteps),
      ingredients: this.lines(this.editIngredients),
      seasonings: this.lines(this.editSeasonings),
      experience: this.lines(this.editExperience),
      photoPath: this.detailPhotoPath,
      originalText: this.detailOriginalText,
      createdAt: this.detailCreatedAt,
      updatedAt: Date.now()
    };
    try {
      await this.repository.update(updated);
      await this.refreshRecipes();
      this.openRecipe(updated);
      this.isEditingDetail = false;
      this.statusMessage = '';
    } catch {
      this.statusMessage = '修改没有保存成功，请重试';
    }
  }

  private async replaceDetailPhoto(): Promise<void> {
    if (this.repository === null || this.detailId.length === 0) {
      this.statusMessage = '菜谱夹还没有准备好';
      return;
    }
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const path: string = await pickRecipePhoto(context, true);
      if (path.length > 0) {
        const updated: RecipeRecord = {
          id: this.detailId,
          name: this.detailName,
          steps: this.detailSteps,
          ingredients: this.detailIngredients,
          seasonings: this.detailSeasonings,
          experience: this.detailExperience,
          photoPath: path,
          originalText: this.detailOriginalText,
          createdAt: this.detailCreatedAt,
          updatedAt: Date.now()
        };
        await this.repository.update(updated);
        await this.refreshRecipes();
        this.openRecipe(updated);
        this.statusMessage = '';
      }
    } catch {
      this.statusMessage = '封面没有保存成功，请重试';
    }
  }

  private async confirmDelete(): Promise<void> {
    if (this.repository === null) {
      return;
    }
    const deletedId: string = this.detailId;
    const deletedName: string = this.detailName;
    await this.repository.softDelete(deletedId);
    this.showDeleteConfirm = false;
    this.closeDetail();
    await this.refreshRecipes();
    this.pendingDeletedId = deletedId;
    this.pendingDeletedName = deletedName;
    this.undoVisible = true;
    setTimeout(() => this.finalizeDelete(deletedId), 5000);
  }

  private async finalizeDelete(id: string): Promise<void> {
    if (this.pendingDeletedId !== id || this.repository === null) {
      return;
    }
    await this.repository.hardDelete(id);
    this.pendingDeletedId = '';
    this.pendingDeletedName = '';
    this.undoVisible = false;
  }

  private async undoDelete(): Promise<void> {
    if (this.repository === null || this.pendingDeletedId.length === 0) {
      return;
    }
    const id: string = this.pendingDeletedId;
    this.pendingDeletedId = '';
    this.undoVisible = false;
    await this.repository.restore(id);
    await this.refreshRecipes();
  }

  private formatDate(timestamp: number): string {
    const date: Date = new Date(timestamp);
    const month: string = `${date.getMonth() + 1}`.padStart(2, '0');
    const day: string = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}.${month}.${day}`;
  }

  private cleanEstimate(item: string): string {
    return item.replace('（AI估算）', '');
  }

  @Builder
  private AssistantAvatar() {
    Stack() {
      Text('厨')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .width(32)
    .height(32)
    .backgroundColor(JADE)
    .borderRadius(10)
  }

  @Builder
  private AssistantBubble(text: string) {
    Row({ space: 10 }) {
      this.AssistantAvatar()
      Text(text)
        .fontSize(15)
        .lineHeight(22)
        .fontColor(INK)
        .padding({ left: 14, right: 14, top: 11, bottom: 11 })
        .backgroundColor(CARD)
        .borderRadius({ topLeft: 4, topRight: 16, bottomLeft: 16, bottomRight: 16 })
        .constraintSize({ maxWidth: '78%' })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private UserBubble(text: string) {
    Row() {
      Blank()
      Text(text)
        .fontSize(15)
        .lineHeight(22)
        .fontColor('#FFFFFF')
        .padding({ left: 14, right: 14, top: 11, bottom: 11 })
        .backgroundColor(JADE)
        .borderRadius({ topLeft: 16, topRight: 4, bottomLeft: 16, bottomRight: 16 })
        .constraintSize({ maxWidth: '82%' })
    }
    .width('100%')
  }

  @Builder
  private EstimateItem(item: string) {
    Row({ space: 7 }) {
      Text(this.cleanEstimate(item))
        .layoutWeight(1)
        .fontSize(14)
        .fontColor(INK)
      if (item.includes('AI估算')) {
        Text('AI 估算')
          .fontSize(10)
          .fontColor(ESTIMATE_TEXT)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor(ESTIMATE)
          .borderRadius(8)
      }
    }
    .width('100%')
    .padding({ top: 7, bottom: 7 })
  }

  @Builder
  private DraftTextList(title: string, items: string[]) {
    Column({ space: 5 }) {
      Text(title)
        .width('100%')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(JADE)
        .letterSpacing(0.5)
      if (items.length === 0) {
        Text('没有补充，不影响保存')
          .width('100%')
          .fontSize(13)
          .fontColor(MUTED)
          .padding({ top: 6, bottom: 6 })
      } else {
        ForEach(items, (item: string) => {
          this.EstimateItem(item)
        }, (item: string) => item)
      }
    }
    .width('100%')
  }

  @Builder
  private DraftRecipeCard() {
    Row() {
      Column({ space: 8 }) {
        ForEach([0, 1, 2, 3, 4, 5, 6], () => {
          Circle().width(6).height(6).fill('#B7C6BD')
        })
      }
      .width(18)
      .height('100%')
      .justifyContent(FlexAlign.SpaceAround)

      Column({ space: 16 }) {
        Row() {
          Column({ space: 4 }) {
            Text('整理好的菜谱')
              .width('100%')
              .fontSize(11)
              .fontColor(CHILI)
              .letterSpacing(1)
            Text(this.draftName)
              .width('100%')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(INK)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text('私房')
            .fontSize(12)
            .fontColor('#FFFFFF')
            .textAlign(TextAlign.Center)
            .width(42)
            .height(42)
            .backgroundColor(CHILI)
            .borderRadius(4)
        }
        .width('100%')

        Row({ space: 10 }) {
          Text(`${this.draftIngredients.length} 种食材`)
            .fontSize(12)
            .fontColor(MUTED)
          Text('·').fontColor('#B5BBB7')
          Text(`${this.draftSteps.length} 个步骤`)
            .fontSize(12)
            .fontColor(MUTED)
        }
        .width('100%')

        Divider().color(LINE)
        this.DraftTextList('食材及用量', this.draftIngredients)
        this.DraftTextList('调料及用量', this.draftSeasonings)

        Column({ space: 10 }) {
          Text('制作步骤')
            .width('100%')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(JADE)
          ForEach(this.draftSteps, (step: string, index: number) => {
            Row({ space: 10 }) {
              Text(`${index + 1}`)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .textAlign(TextAlign.Center)
                .width(25)
                .height(25)
                .backgroundColor(JADE)
                .borderRadius(13)
              Text(step)
                .layoutWeight(1)
                .fontSize(14)
                .lineHeight(21)
                .fontColor(INK)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (step: string, index: number) => `${index}-${step}`)
        }
        .width('100%')

        this.DraftTextList('经验建议', this.draftExperience)

        Text('继续在下方告诉我怎么改，例如“老抽改成半勺”')
          .width('100%')
          .fontSize(12)
          .lineHeight(18)
          .fontColor(MUTED)
          .padding(10)
          .backgroundColor('#EEF3EF')
          .borderRadius(10)

        Button('完成菜谱')
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(this.canFinishDraft() ? CHILI : '#AEB6B1')
          .borderRadius(14)
          .enabled(this.canFinishDraft())
          .onClick(() => this.finishDraft())
      }
      .layoutWeight(1)
      .padding({ left: 8, right: 18, top: 18, bottom: 18 })
    }
    .width('100%')
    .backgroundColor(CARD)
    .borderRadius(18)
    .border({ width: 1, color: '#D7DFDA' })
    .shadow({ radius: 14, color: '#12000000', offsetY: 4 })
  }

  @Builder
  private ConversationPage() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('厨房主理人')
            .width('100%')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(JADE)
          Text(this.hasDraft ? '草稿已自动保存在本机' : '把做成功的味道记下来')
            .width('100%')
            .fontSize(12)
            .fontColor(MUTED)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (this.hasDraft || this.hasQuestion || this.composerText.length > 0) {
          Button('重新记录')
            .fontSize(12)
            .fontColor(CHILI)
            .backgroundColor('#00000000')
            .height(36)
            .onClick(() => {
              this.showDiscardConfirm = true;
            })
        } else {
          Text('本地演示')
            .fontSize(11)
            .fontColor(JADE)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(JADE_SOFT)
            .borderRadius(14)
        }
      }
      .width('100%')
      .height(68)
      .padding({ left: 18, right: 18 })
      .backgroundColor(CARD)

      Scroll() {
        Column({ space: 14 }) {
          this.AssistantBubble('今天做了什么好吃的？直接说菜名、用料和做法，我会在对话里整理成菜谱。')

          if (this.originalText.length > 0) {
            this.UserBubble(this.originalText)
          }

          if (this.hasQuestion) {
            this.AssistantBubble(this.questionText)
          }

          if (this.hasDraft) {
            if (this.latestInstruction.length > 0) {
              this.UserBubble(this.latestInstruction)
            }
            this.AssistantBubble(this.assistantReply.length > 0 ? this.assistantReply : '我整理成卡片了，你可以继续告诉我怎么改。')
            this.DraftRecipeCard()
          }

          if (this.statusMessage.length > 0) {
            Text(this.statusMessage)
              .width('100%')
              .fontSize(13)
              .fontColor('#A44332')
              .textAlign(TextAlign.Center)
              .padding(10)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 18, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      Column({ space: 8 }) {
        Row({ space: 10 }) {
          TextArea({
            text: this.composerText,
            placeholder: this.hasDraft ? '告诉我哪里要改…' : (this.hasQuestion ? '补充关键信息…' : '描述这道菜的做法…')
          })
            .layoutWeight(1)
            .height(58)
            .fontSize(15)
            .fontColor(INK)
            .placeholderColor('#929B96')
            .backgroundColor('#EDF1EE')
            .borderRadius(16)
            .padding({ left: 13, right: 13, top: 10, bottom: 10 })
            .onChange((value: string) => {
              this.composerText = value;
              this.statusMessage = '';
              if (!this.hasDraft && !this.hasQuestion) {
                this.persistDraft();
              }
            })
          Button('↑', { type: ButtonType.Circle })
            .width(48)
            .height(48)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .backgroundColor(this.composerText.trim().length > 0 ? JADE : '#AEB6B1')
            .enabled(this.composerText.trim().length > 0 && !this.isWorking)
            .accessibilityText(this.hasDraft ? '发送修改' : '整理成菜谱')
            .onClick(() => this.sendMessage())
        }
        .width('100%')

        Text('可使用系统输入法语音输入 · 对话框不识别照片')
          .width('100%')
          .fontSize(10)
          .fontColor(MUTED)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 9 })
      .backgroundColor(CARD)
      .border({ width: { top: 1 }, color: LINE })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
  }

  @Builder
  private DefaultCover(name: string, coverHeight: number) {
    Stack() {
      Text(name.length > 0 ? name.slice(0, 1) : '菜')
        .fontSize(coverHeight > 150 ? 52 : 28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
      Text('私房菜谱')
        .fontSize(10)
        .fontColor('#DCE8E1')
        .position({ x: 12, y: 10 })
    }
    .width('100%')
    .height(coverHeight)
    .backgroundColor(JADE)
    .borderRadius(16)
  }

  @Builder
  private RecipeListCard(recipe: RecipeRecord) {
    Row({ space: 13 }) {
      Stack() {
        if (recipe.photoPath.length > 0) {
          Image(recipe.photoPath)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Text(recipe.name.slice(0, 1))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
      }
      .width(78)
      .height(78)
      .backgroundColor(JADE)
      .borderRadius(14)
      .clip(true)

      Column({ space: 7 }) {
        Text(recipe.name)
          .width('100%')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(recipe.ingredients.length > 0 ? recipe.ingredients.map((item: string) => this.cleanEstimate(item).split('·')[0].trim()).slice(0, 3).join('、') : '还没有填写食材')
          .width('100%')
          .fontSize(13)
          .fontColor(MUTED)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Text(`${recipe.steps.length} 步`)
            .layoutWeight(1)
            .fontSize(12)
            .fontColor(MUTED)
          Text(this.formatDate(recipe.createdAt))
            .fontSize(12)
            .fontColor(MUTED)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(13)
    .backgroundColor(recipe.id === this.highlightedRecipeId ? '#E4EFE8' : CARD)
    .border({ width: recipe.id === this.highlightedRecipeId ? 2 : 1, color: recipe.id === this.highlightedRecipeId ? '#79A68F' : LINE })
    .borderRadius(18)
    .onClick(() => this.openRecipe(recipe))
  }

  @Builder
  private RecipeLibraryPage() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 3 }) {
          Text('我的菜谱夹')
            .width('100%')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(JADE)
          Text(`${this.recipes.length} 道家常味道`)
            .width('100%')
            .fontSize(13)
            .fontColor(MUTED)
        }
        .layoutWeight(1)
        Text('私房')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .width(44)
          .height(44)
          .backgroundColor(CHILI)
          .borderRadius(5)
      }
      .width('100%')

      Search({ value: this.searchText, placeholder: '搜菜名、食材或调料' })
        .width('100%')
        .height(44)
        .backgroundColor(CARD)
        .borderRadius(14)
        .onChange((value: string) => this.searchRecipes(value))

      if (this.visibleRecipes.length === 0) {
        Column({ space: 12 }) {
          Text(this.searchText.length > 0 ? '没有找到这道味道' : '菜谱夹还是空的')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(INK)
          Text(this.searchText.length > 0 ? '换个菜名或食材试试' : '点击下方 +，从一段做法开始记录')
            .fontSize(13)
            .fontColor(MUTED)
          if (this.searchText.length === 0) {
            Button('记录第一道菜')
              .fontColor('#FFFFFF')
              .backgroundColor(JADE)
              .borderRadius(14)
              .onClick(() => {
                this.currentPage = 1;
              })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.visibleRecipes, (recipe: RecipeRecord) => {
            ListItem() {
              this.RecipeListCard(recipe)
            }
          }, (recipe: RecipeRecord) => recipe.id)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 20, bottom: 12 })
    .backgroundColor(PAPER)
  }

  @Builder
  private DetailListSection(title: string, items: string[], numbered: boolean) {
    Column({ space: 10 }) {
      Text(title)
        .width('100%')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(JADE)
      if (items.length === 0) {
        Text('未记录')
          .width('100%')
          .fontSize(14)
          .fontColor(MUTED)
      } else {
        ForEach(items, (item: string, index: number) => {
          Row({ space: 10 }) {
            if (numbered) {
              Text(`${index + 1}`)
                .fontSize(11)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .textAlign(TextAlign.Center)
                .width(24)
                .height(24)
                .backgroundColor(JADE)
                .borderRadius(12)
            } else {
              Circle().width(6).height(6).fill(CHILI)
            }
            Text(this.cleanEstimate(item))
              .layoutWeight(1)
              .fontSize(15)
              .lineHeight(22)
              .fontColor(INK)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }, (item: string, index: number) => `${index}-${item}`)
      }
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  private DetailEditPage() {
    Scroll() {
      Column({ space: 15 }) {
        Text('编辑菜谱')
          .width('100%')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(JADE)
        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .width('100%')
            .fontSize(13)
            .fontColor(CHILI)
            .padding({ left: 2, right: 2 })
        }
        TextInput({ text: this.editName, placeholder: '菜名' })
          .width('100%')
          .height(48)
          .fontSize(18)
          .backgroundColor(CARD)
          .borderRadius(12)
          .onChange((value: string) => this.editName = value)
        this.EditArea('食材及用量（每行一项）', this.editIngredients, 100, 0)
        this.EditArea('调料及用量（每行一项）', this.editSeasonings, 100, 1)
        this.EditArea('制作步骤（每行一步）', this.editSteps, 160, 2)
        this.EditArea('经验建议（每行一条）', this.editExperience, 110, 3)
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(46)
            .fontColor(JADE)
            .backgroundColor(JADE_SOFT)
            .borderRadius(14)
            .onClick(() => this.isEditingDetail = false)
          Button('保存修改')
            .layoutWeight(1)
            .height(46)
            .fontColor('#FFFFFF')
            .backgroundColor(JADE)
            .borderRadius(14)
            .onClick(() => this.saveDetailChanges())
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18, bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(PAPER)
  }

  @Builder
  private EditArea(title: string, value: string, areaHeight: number, kind: number) {
    Column({ space: 7 }) {
      Text(title)
        .width('100%')
        .fontSize(13)
        .fontColor(MUTED)
      TextArea({ text: value, placeholder: '未填写' })
        .width('100%')
        .height(areaHeight)
        .fontSize(15)
        .lineHeight(22)
        .fontColor(INK)
        .backgroundColor(CARD)
        .borderRadius(12)
        .padding(12)
        .onChange((text: string) => {
          if (kind === 0) {
            this.editIngredients = text;
          } else if (kind === 1) {
            this.editSeasonings = text;
          } else if (kind === 2) {
            this.editSteps = text;
          } else {
            this.editExperience = text;
          }
        })
    }
    .width('100%')
  }

  @Builder
  private RecipeDetailPage() {
    if (this.isEditingDetail) {
      this.DetailEditPage()
    } else {
      Column() {
        Row() {
          Button('‹')
            .width(40)
            .height(40)
            .fontSize(28)
            .fontColor(JADE)
            .backgroundColor('#00000000')
            .onClick(() => this.closeDetail())
          Text('菜谱详情')
            .layoutWeight(1)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(INK)
          Button('编辑')
            .height(36)
            .fontSize(13)
            .fontColor('#FFFFFF')
            .backgroundColor(JADE)
            .borderRadius(12)
            .onClick(() => this.beginDetailEdit())
        }
        .width('100%')
        .height(58)
        .padding({ left: 8, right: 14 })
        .backgroundColor(CARD)

        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .width('100%')
            .fontSize(13)
            .fontColor(CHILI)
            .padding({ left: 16, right: 16, top: 8, bottom: 2 })
        }

        Scroll() {
          Column({ space: 18 }) {
            Stack({ alignContent: Alignment.BottomStart }) {
              if (this.detailPhotoPath.length > 0) {
                Image(this.detailPhotoPath)
                  .width('100%')
                  .height(230)
                  .objectFit(ImageFit.Cover)
              } else {
                this.DefaultCover(this.detailName, 230)
              }
              Text('更换封面')
                .fontSize(12)
                .fontColor('#FFFFFF')
                .padding({ left: 11, right: 11, top: 7, bottom: 7 })
                .backgroundColor('#9917231F')
                .borderRadius(12)
                .margin(12)
                .onClick(() => this.replaceDetailPhoto())
            }
            .width('100%')
            .height(230)
            .borderRadius(18)
            .clip(true)

            Column({ space: 6 }) {
              Text(this.detailName)
                .width('100%')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(INK)
              Text(`创建于 ${this.formatDate(this.detailCreatedAt)} · 最近修改 ${this.formatDate(this.detailUpdatedAt)}`)
                .width('100%')
                .fontSize(12)
                .fontColor(MUTED)
            }
            .width('100%')

            Column({ space: 14 }) {
              this.DetailListSection('食材及用量', this.detailIngredients, false)
              Divider().color(LINE)
              this.DetailListSection('调料及用量', this.detailSeasonings, false)
              Divider().color(LINE)
              this.DetailListSection('制作步骤', this.detailSteps, true)
              Divider().color(LINE)
              this.DetailListSection('经验建议', this.detailExperience, false)
            }
            .width('100%')
            .padding(18)
            .backgroundColor(CARD)
            .borderRadius(18)

            Button('删除这道菜谱')
              .width('100%')
              .height(44)
              .fontSize(14)
              .fontColor('#A44332')
              .backgroundColor('#F8E7E3')
              .borderRadius(14)
              .onClick(() => this.showDeleteConfirm = true)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 28 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(PAPER)
    }
  }

  @Builder
  private ProfileRow(title: string, content: string, badge: string) {
    Column({ space: 7 }) {
      Row() {
        Text(title)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(INK)
        if (badge.length > 0) {
          Text(badge)
            .fontSize(11)
            .fontColor(JADE)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(JADE_SOFT)
            .borderRadius(10)
        }
      }
      .width('100%')
      Text(content)
        .width('100%')
        .fontSize(13)
        .lineHeight(20)
        .fontColor(MUTED)
    }
    .width('100%')
    .padding({ top: 15, bottom: 15 })
  }

  @Builder
  private ProfilePage() {
    Scroll() {
      Column({ space: 16 }) {
        Text('我的')
          .width('100%')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(JADE)
        Column() {
          this.ProfileRow('本机菜谱', `${this.recipes.length} 道菜保存在当前设备`, '本地优先')
          Divider().color(LINE)
          this.ProfileRow('AI 服务', '当前是本地演示整理，尚未连接腾讯云上的 DeepSeek 服务。', '演示模式')
          Divider().color(LINE)
          this.ProfileRow('隐私说明', '对话框只处理文字；照片只作为本地菜谱封面，不用于识别，也不会上传。', '')
          Divider().color(LINE)
          this.ProfileRow('关于厨房主理人', '把一次做成功的经验，整理成以后还能复刻的家庭菜谱。', '0.1.0-demo')
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .backgroundColor(CARD)
        .borderRadius(18)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20, bottom: 26 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(PAPER)
  }

  @Builder
  private NavItem(label: string, symbol: string, page: number) {
    Column({ space: 2 }) {
      Text(symbol)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.currentPage === page ? JADE : '#8A938E')
      Text(label)
        .fontSize(11)
        .fontWeight(this.currentPage === page ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.currentPage === page ? JADE : '#8A938E')
    }
    .width(84)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentPage = page;
      if (page === 0) {
        this.closeDetail();
      }
    })
  }

  @Builder
  private BottomNavigation() {
    Row() {
      this.NavItem('菜谱', '▤', 0)
      Blank()
      Button('+', { type: ButtonType.Circle })
        .width(56)
        .height(56)
        .fontSize(28)
        .fontWeight(FontWeight.Lighter)
        .fontColor('#FFFFFF')
        .backgroundColor(CHILI)
        .shadow({ radius: 12, color: '#44D95D42', offsetY: 5 })
        .accessibilityText('记录一道菜')
        .onClick(() => {
          this.currentPage = 1;
          this.closeDetail();
        })
        .translate({ y: -8 })
      Blank()
      this.NavItem('我的', '●', 2)
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 16 })
    .backgroundColor(CARD)
    .border({ width: { top: 1 }, color: LINE })
  }

  @Builder
  private PhotoPrompt() {
    Column() {
      Blank()
      Column({ space: 11 }) {
        Row() {
          Text('给菜谱加张成品照吗？')
            .layoutWeight(1)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(INK)
          Button('×')
            .width(34)
            .height(34)
            .fontSize(20)
            .fontColor(MUTED)
            .backgroundColor('#EDF1EE')
            .borderRadius(17)
            .onClick(() => this.showPhotoPrompt = false)
        }
        .width('100%')
        Text('照片只作为菜谱封面，不会用于识别或修改菜谱内容。')
          .width('100%')
          .fontSize(13)
          .lineHeight(20)
          .fontColor(MUTED)
        Button('拍一张')
          .width('100%')
          .height(46)
          .fontColor('#FFFFFF')
          .backgroundColor(JADE)
          .borderRadius(14)
          .onClick(() => this.pickPhotoAndArchive(true))
        Button('从相册选择')
          .width('100%')
          .height(46)
          .fontColor(JADE)
          .backgroundColor(JADE_SOFT)
          .borderRadius(14)
          .onClick(() => this.pickPhotoAndArchive(false))
        Button('暂时不要，使用默认封面')
          .width('100%')
          .height(42)
          .fontSize(13)
          .fontColor(MUTED)
          .backgroundColor('#00000000')
          .onClick(() => this.archiveDraft(''))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 20, bottom: 24 })
      .backgroundColor(CARD)
      .borderRadius({ topLeft: 24, topRight: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#66000000')
  }

  @Builder
  private ConfirmDialog(title: string, message: string, kind: number) {
    Column() {
      Blank()
      Column({ space: 14 }) {
        Text(title)
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(INK)
        Text(message)
          .width('100%')
          .fontSize(14)
          .lineHeight(21)
          .fontColor(MUTED)
        Row({ space: 10 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .fontColor(JADE)
            .backgroundColor(JADE_SOFT)
            .borderRadius(14)
            .onClick(() => {
              this.showDeleteConfirm = false;
              this.showDiscardConfirm = false;
            })
          Button(kind === 0 ? '删除' : '放弃草稿')
            .layoutWeight(1)
            .height(44)
            .fontColor('#FFFFFF')
            .backgroundColor(CHILI)
            .borderRadius(14)
            .onClick(() => {
              if (kind === 0) {
                this.confirmDelete();
              } else {
                this.discardDraft();
              }
            })
        }
        .width('100%')
      }
      .width('88%')
      .padding(20)
      .backgroundColor(CARD)
      .borderRadius(20)
      Blank()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#66000000')
  }

  @Builder
  private ArchiveOverlay() {
    Column({ space: 9 }) {
      Text('正在收进菜谱夹')
        .fontSize(11)
        .fontColor(CHILI)
      Text(this.archiveName)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(INK)
      Divider().color(LINE)
      Text('这次做成功的味道，已经记住了。')
        .fontSize(13)
        .fontColor(MUTED)
    }
    .width('78%')
    .height(180)
    .padding(20)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(CARD)
    .border({ width: 1, color: LINE })
    .borderRadius(18)
    .shadow({ radius: 20, color: '#33000000', offsetY: 8 })
    .scale({ x: this.archiveScale, y: this.archiveScale })
    .translate({ x: this.archiveX, y: this.archiveY })
    .opacity(this.archiveOpacity)
    .align(Alignment.Center)
  }

  @Builder
  private UndoBar() {
    Column() {
      Blank()
      Row({ space: 10 }) {
        Text(`已删除“${this.pendingDeletedName}”`)
          .layoutWeight(1)
          .fontSize(13)
          .fontColor('#FFFFFF')
        Button('撤销')
          .height(34)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(CHILI)
          .borderRadius(10)
          .onClick(() => this.undoDelete())
      }
      .width('92%')
      .padding({ left: 14, right: 8, top: 8, bottom: 8 })
      .backgroundColor('#E617231F')
      .borderRadius(14)
      .margin({ bottom: 84 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      Column() {
        Stack() {
          if (this.currentPage === 0 && this.detailId.length > 0) {
            this.RecipeDetailPage()
          } else if (this.currentPage === 0) {
            this.RecipeLibraryPage()
          } else if (this.currentPage === 2) {
            this.ProfilePage()
          } else {
            this.ConversationPage()
          }
        }
        .width('100%')
        .layoutWeight(1)
        this.BottomNavigation()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(PAPER)

      if (this.archiveAnimating) {
        this.ArchiveOverlay()
      }
      if (this.showPhotoPrompt) {
        this.PhotoPrompt()
      }
      if (this.showDeleteConfirm) {
        this.ConfirmDialog('删除这道菜谱？', '删除后有 5 秒可以撤销，之后会从本机菜谱夹中移除。', 0)
      }
      if (this.showDiscardConfirm) {
        this.ConfirmDialog('放弃当前草稿？', '已经整理的内容会被清空，这个操作不能恢复。', 1)
      }
      if (this.undoVisible) {
        this.UndoBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
  }
}
