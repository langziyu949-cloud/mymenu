import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { authentication, LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import { IDENTITY_VERIFICATION_ENABLED } from '../config/ComplianceConfig';
import { RecipeRepository } from '../data/RecipeRepository';
import { DraftRecipeVersion, DraftSession, RecipeDraft, RecipeRecord } from '../models/RecipeModels';
import { persistRecipePhoto, pickRecipePhotoUri } from '../services/PhotoPickerService';
import {
  identityVerificationService,
  IdentityVerificationResult
} from '../services/IdentityVerificationService';
import {
  AiAnalyzeResult,
  AiClarifyingAnswer,
  AiClarifyingQuestion,
  AiRecipeDraft,
  AiRecipeItem,
  AiRevisionResult,
  RecipeAiService,
  RecipeAiServiceError
} from '../services/RecipeAiService';

const PAPER: string = '#F2F5F1';
const CARD: string = '#FCFDFB';
const INK: string = '#17231F';
const JADE: string = '#173F34';
const JADE_SOFT: string = '#DCE8E1';
const CHILI: string = '#D95D42';
const MUTED: string = '#5F6964';
const LINE: string = '#DDE3DF';
const ESTIMATE: string = '#FFF0D8';
const ESTIMATE_TEXT: string = '#8A5B13';
const INGREDIENT_AMOUNTS: string[] = ['少许', '适量', '1个', '2个', '半个', '1斤', '半斤'];
const SEASONING_AMOUNTS: string[] = ['少许', '适量', '1勺', '2勺', '半勺', '几滴'];

interface ClarificationTurn {
  userText: string;
  assistantText: string;
}

interface ConversationMessage {
  id: string;
  role: number;
  text: string;
}

@Entry
@Component
struct Index {
  @State currentPage: number = 1;
  @State composerText: string = '';
  @State originalText: string = '';
  @State hasDraft: boolean = false;
  @State hasQuestion: boolean = false;
  @State questionText: string = '';
  @State questionIds: string[] = [];
  @State latestInstruction: string = '';
  @State assistantReply: string = '';
  @State clarificationTurns: ClarificationTurn[] = [];
  @State conversationMessages: ConversationMessage[] = [];
  @State conversationMessageRevision: number = 0;
  @State draftHistory: DraftRecipeVersion[] = [];
  @State draftRenderRevision: number = 0;
  @State draftName: string = '';
  @State draftSteps: string[] = [];
  @State draftIngredients: string[] = [];
  @State draftSeasonings: string[] = [];
  @State draftExperience: string[] = [];
  @State statusMessage: string = '';
  @State isWorking: boolean = false;
  @State pendingUserMessage: string = '';
  @State aiOnline: boolean = false;
  @State identityVerified: boolean = false;
  @State acceptedAiTerms: boolean = false;
  @State verificationMessage: string = '';
  @State identityMethod: string = '';
  @State verifiedAccountLabel: string = '';
  @State verifiedDisplayName: string = '';
  @State verifiedAccountId: string = '';
  @State verifiedAvatarUrl: string = '';
  @State verifiedLoginAt: number = 0;
  @State showHuaweiLogoutConfirm: boolean = false;
  @State showDraftRecipeDetail: boolean = false;
  @State profileDetailKind: number = 0;
  @State loginPolicyDetailKind: number = 0;

  @State recipes: RecipeRecord[] = [];
  @State visibleRecipes: RecipeRecord[] = [];
  @State searchText: string = '';
  @State highlightedRecipeId: string = '';
  @State recipeLayoutMode: number = 0;

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
  @State editSectionIndex: number = 0;
  @State editSteps: string[] = [];
  @State editStepIds: string[] = [];
  @State editIngredientNames: string[] = [];
  @State editIngredientAmounts: string[] = [];
  @State editIngredientEstimated: boolean[] = [];
  @State editIngredientIds: string[] = [];
  @State editSeasoningNames: string[] = [];
  @State editSeasoningAmounts: string[] = [];
  @State editSeasoningEstimated: boolean[] = [];
  @State editSeasoningIds: string[] = [];
  @State editExperience: string[] = [];
  @State editExperienceIds: string[] = [];
  @State editDragPreviewText: string = '';
  @State editDragPreviewAmount: string = '';
  @State editDragPreviewMeasured: boolean = false;
  @State editDraggedId: string = '';
  @State editFeedbackMessage: string = '';

  @State showPhotoPrompt: boolean = false;
  @State showPhotoConfirm: boolean = false;
  @State pendingPhotoUri: string = '';
  @State pendingPhotoTarget: number = 0;
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
  private readonly aiService: RecipeAiService = new RecipeAiService();
  private readonly huaweiLoginController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController();
  private readonly conversationScroller: Scroller = new Scroller();
  private readonly ingredientEditScroller: Scroller = new Scroller();
  private readonly seasoningEditScroller: Scroller = new Scroller();
  private readonly stepEditScroller: Scroller = new Scroller();
  private readonly experienceEditScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    if (IDENTITY_VERIFICATION_ENABLED) {
      this.configureHuaweiAccountLogin();
    }
    this.initialize();
  }

  onBackPress(): boolean {
    if (this.showPhotoConfirm) {
      this.cancelPendingPhoto();
      return true;
    }
    if (this.showPhotoPrompt) {
      this.showPhotoPrompt = false;
      return true;
    }
    if (this.showDeleteConfirm || this.showDiscardConfirm || this.showHuaweiLogoutConfirm) {
      this.showDeleteConfirm = false;
      this.showDiscardConfirm = false;
      this.showHuaweiLogoutConfirm = false;
      return true;
    }
    if (this.loginPolicyDetailKind > 0) {
      this.loginPolicyDetailKind = 0;
      return true;
    }
    if (this.profileDetailKind > 0) {
      this.profileDetailKind = 0;
      return true;
    }
    if (this.currentPage === 0 && this.detailId.length > 0) {
      if (this.isEditingDetail) {
        this.isEditingDetail = false;
      } else {
        this.closeDetail();
      }
      return true;
    }
    if (this.showDraftRecipeDetail) {
      this.returnToConversation();
      return true;
    }
    if (this.archiveAnimating) {
      return true;
    }
    return false;
  }

  private configureHuaweiAccountLogin(): void {
    this.huaweiLoginController
      .setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED)
      .onClickLoginWithHuaweiIDButton((error: BusinessError,
        credential: loginComponentManager.HuaweiIDCredential) => {
        if (error) {
          if (error.code === 1005300001) {
            this.verificationMessage = '请先阅读并同意 AI 服务规则和隐私政策';
          } else if (error.code !== 1001502012) {
            this.verificationMessage = this.huaweiLoginErrorMessage(error.code);
          }
          return;
        }
        // The native component can retain its previous agreement state after an
        // account logout. Keep the application's own check as the final gate.
        if (!this.acceptedAiTerms) {
          this.huaweiLoginController.setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED);
          this.verificationMessage = '请先阅读并同意 AI 服务规则和隐私政策';
          return;
        }
        void this.handleHuaweiAccountCredential(credential);
      });
  }

  private updateHuaweiAgreement(accepted: boolean): void {
    this.acceptedAiTerms = accepted;
    this.verificationMessage = '';
    this.huaweiLoginController.setAgreementStatus(accepted ?
      loginComponentManager.AgreementStatus.ACCEPTED :
      loginComponentManager.AgreementStatus.NOT_ACCEPTED);
  }

  private async handleHuaweiAccountCredential(credential: loginComponentManager.HuaweiIDCredential): Promise<void> {
    if (!this.acceptedAiTerms) {
      this.huaweiLoginController.setAgreementStatus(loginComponentManager.AgreementStatus.NOT_ACCEPTED);
      this.verificationMessage = '请先阅读并同意 AI 服务规则和隐私政策';
      return;
    }
    if (credential.authorizationCode.length === 0) {
      this.verificationMessage = '未取得华为账号授权码，请重试';
      return;
    }
    this.verificationMessage = '正在读取华为账号资料…';
    try {
      const authorizationCode: string = await this.requestHuaweiAccountProfile(credential.authorizationCode);
      this.verificationMessage = '正在由服务端校验华为账号…';
      const result: IdentityVerificationResult =
        await identityVerificationService.verifyHuaweiAccount(authorizationCode);
      this.applyVerifiedIdentity(result);
      this.verificationMessage = '';
      this.statusMessage = '';
    } catch {
      this.verificationMessage = '华为账号授权已完成，但服务端登录失败，请稍后重试';
    }
  }

  private async requestHuaweiAccountProfile(loginAuthorizationCode: string): Promise<string> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
      const request: authentication.AuthorizationWithHuaweiIDRequest =
        provider.createAuthorizationWithHuaweiIDRequest();
      request.scopes = ['profile'];
      request.permissions = ['serviceauthcode'];
      request.forceAuthorization = true;
      const controller: authentication.AuthenticationController =
        new authentication.AuthenticationController(context);
      const response: authentication.AuthenticationResponse = await controller.executeRequest(request);
      const authorizationResponse: authentication.AuthorizationWithHuaweiIDResponse =
        response as authentication.AuthorizationWithHuaweiIDResponse;
      const profileAuthorizationCode: string | undefined = authorizationResponse.data?.authorizationCode;
      if (profileAuthorizationCode !== undefined && profileAuthorizationCode.length > 0) {
        return profileAuthorizationCode;
      }
    } catch {
      // Profile authorization is optional. The original login code still proves
      // the account identity and yields an OpenID/UnionID on the server.
    }
    return loginAuthorizationCode;
  }

  private huaweiLoginErrorMessage(code: number): string {
    if (code === 1001502001) {
      return '设备尚未登录华为账号，请先在系统设置中登录';
    }
    if (code === 1001502005) {
      return '网络连接异常，请检查网络后重试';
    }
    if (code === 1001502014 || code === 1001500003) {
      return '应用的华为账号登录权限尚未开通';
    }
    return `华为账号登录暂不可用（${code}），请稍后重试`;
  }

  private async initialize(): Promise<void> {
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      this.repository = await RecipeRepository.create(context);
      await this.refreshRecipes();
      await this.restoreDraft();
      this.rebuildConversationMessages();
      if (IDENTITY_VERIFICATION_ENABLED) {
        const identity: IdentityVerificationResult | null = await identityVerificationService.restoreIdentity();
        if (identity !== null) {
          this.applyVerifiedIdentity(identity);
        }
      }
      this.aiOnline = await this.aiService.isAvailable();
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
    this.originalText = draft.originalText;
    this.questionText = draft.questionText;
    this.questionIds = draft.questionIds;
    if (draft.recipeName.length === 0) {
      if (draft.questionText.length > 0) {
        this.hasQuestion = true;
        this.clarificationTurns = [{ userText: '', assistantText: draft.questionText }];
      } else {
        this.composerText = draft.originalText;
      }
      return;
    }
    this.draftName = draft.recipeName;
    this.draftSteps = draft.steps;
    this.draftIngredients = draft.ingredients;
    this.draftSeasonings = draft.seasonings;
    this.draftExperience = draft.experience;
    this.latestInstruction = draft.lastInstruction;
    this.assistantReply = draft.assistantReply.length > 0 ? draft.assistantReply :
      '未完成的菜谱已经恢复，可以继续告诉我怎么改。';
    this.draftHistory = draft.history;
    this.draftRenderRevision = draft.history.length + 1;
    this.hasDraft = true;
    this.rebuildConversationMessages();
    this.scrollConversationToBottom();
  }

  private async persistDraft(): Promise<void> {
    if (this.repository === null) {
      return;
    }
    const draft: DraftSession = {
      originalText: this.hasDraft || this.hasQuestion ? this.originalText : this.composerText,
      questionText: this.questionText,
      questionIds: this.questionIds,
      recipeName: this.hasDraft ? this.draftName : '',
      steps: this.hasDraft ? this.draftSteps : [],
      ingredients: this.hasDraft ? this.draftIngredients : [],
      seasonings: this.hasDraft ? this.draftSeasonings : [],
      experience: this.hasDraft ? this.draftExperience : [],
      lastInstruction: this.latestInstruction,
      assistantReply: this.assistantReply,
      history: this.hasDraft ? this.draftHistory : [],
      updatedAt: Date.now()
    };
    await this.repository.saveDraft(draft);
  }

  private formatAiItem(item: AiRecipeItem): string {
    const amount: string = item.amount.trim();
    const content: string = amount.length > 0 ? `${item.name} · ${amount}` : item.name;
    return item.isAiEstimated ? `${content}（AI估算）` : content;
  }

  private parseAiItem(value: string): AiRecipeItem {
    const isAiEstimated: boolean = value.includes('AI估算');
    const clean: string = value.replace('（AI估算）', '').trim();
    const delimiter: string = ' · ';
    const index: number = clean.indexOf(delimiter);
    if (index < 0) {
      return { name: clean, amount: '', isAiEstimated };
    }
    return {
      name: clean.slice(0, index).trim(),
      amount: clean.slice(index + delimiter.length).trim(),
      isAiEstimated
    };
  }

  private applyAiRecipe(recipe: AiRecipeDraft): void {
    this.draftName = recipe.name;
    this.draftSteps = recipe.steps;
    this.draftIngredients = recipe.ingredients.map((item: AiRecipeItem) => this.formatAiItem(item));
    this.draftSeasonings = recipe.seasonings.map((item: AiRecipeItem) => this.formatAiItem(item));
    this.draftExperience = recipe.experience;
    this.hasDraft = true;
    this.hasQuestion = false;
    this.questionIds = [];
    this.draftRenderRevision += 1;
    this.rebuildConversationMessages();
    this.scrollConversationToBottom();
  }

  private scrollConversationToBottom(): void {
    setTimeout((): void => this.conversationScroller.scrollEdge(Edge.Bottom), 120);
    setTimeout((): void => this.conversationScroller.scrollEdge(Edge.Bottom), 360);
  }

  private returnToConversation(): void {
    this.showDraftRecipeDetail = false;
    this.rebuildConversationMessages();
    this.scrollConversationToBottom();
  }

  private rebuildConversationMessages(): void {
    const messages: ConversationMessage[] = [];
    let sequence: number = 0;
    const append: (role: number, value: string) => void = (role: number, value: string): void => {
      const text: string = value.trim();
      if (text.length === 0) {
        return;
      }
      sequence += 1;
      messages.push({
        id: `${this.draftRenderRevision}-${sequence}-${role}-${text}`,
        role,
        text
      });
    };
    append(0, '今天做了什么好吃的？直接说菜名、用料和做法，我会在对话里整理成菜谱。');
    append(1, this.originalText);
    this.clarificationTurns.forEach((turn: ClarificationTurn) => {
      append(1, turn.userText);
      append(0, turn.assistantText);
    });
    if (this.clarificationTurns.length === 0) {
      append(0, this.questionText);
    }
    if (this.hasDraft) {
      this.draftHistory.forEach((version: DraftRecipeVersion) => {
        append(1, version.instruction);
        append(0, version.assistantReply.length > 0 ? version.assistantReply : '已经整理成菜谱卡片。');
      });
      append(1, this.latestInstruction);
      append(0, this.assistantReply.length > 0 ? this.assistantReply : '我整理成卡片了，你可以继续告诉我怎么改。');
    }
    this.conversationMessageRevision += 1;
    this.conversationMessages = messages;
  }

  private currentAiRecipe(): AiRecipeDraft {
    return {
      name: this.draftName,
      ingredients: this.draftIngredients.map((item: string) => this.parseAiItem(item)),
      seasonings: this.draftSeasonings.map((item: string) => this.parseAiItem(item)),
      steps: this.draftSteps,
      experience: this.draftExperience
    };
  }

  private currentDraftVersion(): DraftRecipeVersion {
    return {
      recipeName: this.draftName,
      steps: this.draftSteps.slice(),
      ingredients: this.draftIngredients.slice(),
      seasonings: this.draftSeasonings.slice(),
      experience: this.draftExperience.slice(),
      instruction: this.latestInstruction,
      assistantReply: this.assistantReply
    };
  }

  private applyAnalyzeResult(result: AiAnalyzeResult): void {
    if (result.kind === 'guidance') {
      this.hasQuestion = false;
      this.hasDraft = false;
      this.questionIds = [];
      this.questionText = '';
      this.assistantReply = result.reply;
      this.clarificationTurns = [{ userText: '', assistantText: result.reply }];
      return;
    }
    if (result.kind === 'questions') {
      const questions: AiClarifyingQuestion[] = result.questions.slice(0, 3);
      if (questions.length === 0) {
        throw new RecipeAiServiceError('AI_INVALID_RESPONSE', true);
      }
      this.hasQuestion = true;
      this.hasDraft = false;
      this.questionIds = questions.map((question: AiClarifyingQuestion) => question.id);
      this.questionText = questions.map((question: AiClarifyingQuestion, index: number) =>
        `${index + 1}. ${question.text}`).join('\n');
      this.clarificationTurns = [{ userText: '', assistantText: this.questionText }];
      return;
    }
    if (result.recipe === null) {
      throw new RecipeAiServiceError('AI_INVALID_RESPONSE', true);
    }
    this.applyAiRecipe(result.recipe);
  }

  private isClearlyUnrelatedMessage(message: string): boolean {
    const normalized: string = message.trim().toLocaleLowerCase();
    const cookingHints: string[] = [
      '菜', '做', '炒', '煮', '炖', '煎', '炸', '蒸', '烤', '焖', '拌', '切', '锅', '火',
      '食材', '调料', '步骤', '盐', '油', '肉', '蛋', '饭', '面', '汤', '水', '克', '勺',
      '糖', '醋', '酱', '辣', '甜', '酸', '嫩', '软', '脆', '香', '加', '减', '改',
      '少许', '适量', '分钟', '加入', '放入', '换成', '少放', '多放', '不要', '修改'
    ];
    if (cookingHints.some((hint: string) => normalized.includes(hint))) {
      return false;
    }
    const chatOnlyHints: string[] = [
      '你好', '您好', '在吗', '早上好', '晚上好', '恭喜发财', '谢谢', '天气', '讲个笑话'
    ];
    return chatOnlyHints.some((hint: string) => normalized.includes(hint)) ||
      normalized.length <= 4 || /^[a-z\d\s,.!?]+$/i.test(normalized);
  }

  private async handleUnrelatedMessage(message: string): Promise<void> {
    const prompt: string = this.hasDraft ?
      '这条信息看起来不是菜谱修改。你可以告诉我想调整哪种食材、用量或制作步骤。' :
      '这条信息看起来和菜谱无关。请告诉我菜名、食材，或者简单说说制作步骤。';
    this.composerText = '';
    this.pendingUserMessage = '';
    this.statusMessage = '';
    if (this.hasDraft) {
      this.draftHistory = this.draftHistory.concat([this.currentDraftVersion()]);
      this.latestInstruction = message;
      this.assistantReply = prompt;
      this.draftRenderRevision += 1;
    } else if (this.hasQuestion) {
      this.clarificationTurns = this.clarificationTurns.concat([
        { userText: message, assistantText: prompt }
      ]);
      this.questionText = prompt;
    } else {
      this.originalText = message;
      this.hasQuestion = false;
      this.questionText = '';
      this.questionIds = [];
      this.assistantReply = prompt;
      this.clarificationTurns = [{ userText: '', assistantText: prompt }];
    }
    await this.persistDraft();
    this.rebuildConversationMessages();
    this.scrollConversationToBottom();
  }

  private aiErrorMessage(error: Error): string {
    if (error instanceof RecipeAiServiceError) {
      if (error.code === 'UNAUTHORIZED') {
        return 'AI 服务鉴权配置有误，请检查华为云函数配置';
      }
      if (error.code === 'AI_INVALID_RESPONSE') {
        return 'AI 返回的菜谱格式不完整，内容已保留，请重试';
      }
      if (error.code === 'INVALID_REQUEST') {
        return '这段描述暂时无法整理，请补充菜名或制作步骤';
      }
    }
    return '暂时连接不上 AI，内容已保留，请稍后重试';
  }

  private initialRecipeReply(recipe: AiRecipeDraft, modelReply: string): string {
    if (modelReply.trim().length > 0) {
      return modelReply.trim();
    }
    const detail: string = recipe.ingredients.length > 0 ?
      `${recipe.ingredients.length} 种食材和 ${recipe.steps.length} 个步骤都已经归好` :
      `${recipe.steps.length} 个步骤已经按顺序理清`;
    return `“${recipe.name}”听起来很不错，${detail}。有哪处想换个做法，直接告诉我就行。`;
  }

  private revisedRecipeReply(before: AiRecipeDraft, recipe: AiRecipeDraft,
    instruction: string, modelReply: string): string {
    const changes: string[] = this.recipeChangeDescriptions(before, recipe);
    if (changes.length > 0) {
      return `这次${changes.slice(0, 2).join('，')}。其他内容保持不变。`;
    }
    const candidate: string = modelReply.trim();
    const normalizedCandidate: string = this.normalizeReply(candidate);
    const repeatsPreviousReply: boolean = candidate.length > 0 && this.recentAssistantReplies()
      .some((reply: string) => this.normalizeReply(reply) === normalizedCandidate);
    const usesOldTemplate: boolean = candidate.includes('DeepSeek 已按') ||
      (candidate.includes('听起来很不错') && candidate.includes('有哪处想换个做法'));
    if (candidate.length > 0 && !repeatsPreviousReply && !usesOldTemplate) {
      return candidate;
    }
    const cleanInstruction: string = instruction.trim().replace(/[。！!？?]+$/u, '');
    const summary: string = cleanInstruction.length > 26 ? `${cleanInstruction.slice(0, 26)}…` : cleanInstruction;
    return `“${summary}”没有改变当前菜谱。请告诉我想调整的食材、用量或制作步骤。`;
  }

  private normalizeReply(value: string): string {
    return value.replace(/[\s，。！？、；：“”‘’"']/gu, '').toLocaleLowerCase();
  }

  private recipeChangeDescriptions(before: AiRecipeDraft, after: AiRecipeDraft): string[] {
    const changes: string[] = [];
    if (before.name !== after.name) {
      changes.push(`把菜名改成了“${after.name}”`);
    }
    changes.push(...this.itemChangeDescriptions(before.ingredients, after.ingredients, '食材'));
    changes.push(...this.itemChangeDescriptions(before.seasonings, after.seasonings, '调料'));
    if (JSON.stringify(before.steps) !== JSON.stringify(after.steps)) {
      changes.push('制作步骤也同步调整了');
    }
    if (JSON.stringify(before.experience) !== JSON.stringify(after.experience)) {
      changes.push('经验建议已更新');
    }
    return changes;
  }

  private itemChangeDescriptions(before: AiRecipeItem[], after: AiRecipeItem[], label: string): string[] {
    const changes: string[] = [];
    after.forEach((item: AiRecipeItem) => {
      const previous: AiRecipeItem | undefined = before.find((value: AiRecipeItem) => value.name === item.name);
      if (previous === undefined) {
        changes.push(`加入了${item.name}${item.amount.length > 0 ? `（${item.amount}）` : ''}`);
      } else if (previous.amount !== item.amount) {
        changes.push(`${item.name}改为${item.amount.length > 0 ? item.amount : '不标用量'}`);
      }
    });
    before.forEach((item: AiRecipeItem) => {
      if (!after.some((value: AiRecipeItem) => value.name === item.name)) {
        changes.push(`移除了${label}“${item.name}”`);
      }
    });
    return changes;
  }

  private recentAssistantReplies(): string[] {
    const replies: string[] = this.draftHistory
      .map((version: DraftRecipeVersion) => version.assistantReply.trim())
      .filter((reply: string) => reply.length > 0);
    if (this.assistantReply.trim().length > 0) {
      replies.push(this.assistantReply.trim());
    }
    return replies.slice(-6);
  }

  private accountLabel(): string {
    if (this.verifiedAccountLabel.length > 0) {
      return this.verifiedAccountLabel;
    }
    return '';
  }

  private applyVerifiedIdentity(identity: IdentityVerificationResult): void {
    this.identityVerified = true;
    this.identityMethod = '华为账号';
    this.verifiedAccountLabel = identity.accountLabel;
    this.verifiedDisplayName = identity.displayName;
    this.verifiedAccountId = identity.accountId;
    this.verifiedAvatarUrl = identity.avatarUrl;
    this.verifiedLoginAt = identity.loginAt;
  }

  private clearVerifiedIdentity(): void {
    this.identityVerified = false;
    this.identityMethod = '';
    this.verifiedAccountLabel = '';
    this.verifiedDisplayName = '';
    this.verifiedAccountId = '';
    this.verifiedAvatarUrl = '';
    this.verifiedLoginAt = 0;
  }

  private async logoutHuaweiAccount(): Promise<void> {
    this.showHuaweiLogoutConfirm = false;
    let authorizationCancelled: boolean = false;
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const provider: authentication.HuaweiIDProvider = new authentication.HuaweiIDProvider();
      const request: authentication.CancelAuthorizationRequest = provider.createCancelAuthorizationRequest();
      const controller: authentication.AuthenticationController =
        new authentication.AuthenticationController(context);
      await controller.executeRequest(request);
      authorizationCancelled = true;
    } catch {
      authorizationCancelled = false;
    }
    await identityVerificationService.clearIdentity();
    this.clearVerifiedIdentity();
    this.updateHuaweiAgreement(false);
    this.verificationMessage = authorizationCancelled ?
      '已退出华为账号登录，可重新选择账号授权' :
      '已退出本应用；华为账号授权暂未撤销，可稍后重新登录后再试';
    this.currentPage = 1;
  }

  private async sendMessage(): Promise<void> {
    if (IDENTITY_VERIFICATION_ENABLED && !this.identityVerified) {
      this.statusMessage = '请先登录华为账号';
      return;
    }
    const message: string = this.composerText.trim();
    if (message.length === 0) {
      this.statusMessage = '先说说这道菜是怎么做的';
      return;
    }
    if (this.isWorking) {
      this.statusMessage = '正在整理上一条消息，请稍等';
      return;
    }
    if (this.isClearlyUnrelatedMessage(message)) {
      await this.handleUnrelatedMessage(message);
      return;
    }
    this.pendingUserMessage = message;
    this.composerText = '';
    this.isWorking = true;
    this.statusMessage = '';
    this.scrollConversationToBottom();

    try {
      if (!this.hasDraft && !this.hasQuestion) {
        const result: AiAnalyzeResult = await this.aiService.analyze(message);
        this.aiOnline = true;
        this.originalText = message;
        this.clarificationTurns = [];
        this.applyAnalyzeResult(result);
        if (result.kind === 'recipe' && result.recipe !== null) {
          this.assistantReply = this.initialRecipeReply(result.recipe, result.reply);
        } else if (result.kind === 'guidance') {
          this.assistantReply = result.reply;
        } else {
          this.assistantReply = '';
        }
        this.pendingUserMessage = '';
        this.rebuildConversationMessages();
        await this.persistDraft();
        return;
      }

      if (this.hasQuestion && !this.hasDraft) {
        const questionId: string = this.questionIds.length > 0 ? this.questionIds.join(',') : 'combined';
        const earlierAnswers: string[] = this.clarificationTurns
          .map((turn: ClarificationTurn) => turn.userText)
          .filter((answer: string) => answer.length > 0);
        const answers: AiClarifyingAnswer[] = [{
          questionId,
          answer: earlierAnswers.concat([message]).join('\n')
        }];
        const result: AiAnalyzeResult = await this.aiService.analyze(this.originalText, answers);
        this.aiOnline = true;
        if (result.kind === 'questions') {
          const questions: AiClarifyingQuestion[] = result.questions.slice(0, 3);
          if (questions.length === 0) {
            throw new RecipeAiServiceError('AI_INVALID_RESPONSE', true);
          }
          const prompt: string = questions.map((question: AiClarifyingQuestion, index: number) =>
            `${index + 1}. ${question.text}`).join('\n');
          this.questionIds = questions.map((question: AiClarifyingQuestion) => question.id);
          this.questionText = prompt;
          this.clarificationTurns = this.clarificationTurns.concat([
            { userText: message, assistantText: prompt }
          ]);
          this.pendingUserMessage = '';
          this.rebuildConversationMessages();
          await this.persistDraft();
          return;
        }
        if (result.recipe === null) {
          throw new RecipeAiServiceError('AI_INVALID_RESPONSE', true);
        }
        this.clarificationTurns = this.clarificationTurns.concat([
          { userText: message, assistantText: '' }
        ]);
        this.latestInstruction = '';
        this.applyAiRecipe(result.recipe);
        this.assistantReply = this.initialRecipeReply(result.recipe, result.reply);
        this.pendingUserMessage = '';
        this.rebuildConversationMessages();
        await this.persistDraft();
        return;
      }

      const previousRecipe: AiRecipeDraft = this.currentAiRecipe();
      const previousVersion: DraftRecipeVersion = this.currentDraftVersion();
      const revision: AiRevisionResult = await this.aiService.revise(
        previousRecipe, message, this.recentAssistantReplies());
      this.aiOnline = true;
      this.draftHistory = this.draftHistory.concat([previousVersion]);
      this.latestInstruction = message;
      this.assistantReply = this.revisedRecipeReply(previousRecipe, revision.recipe, message, revision.reply);
      this.applyAiRecipe(revision.recipe);
      this.pendingUserMessage = '';
      this.rebuildConversationMessages();
      await this.persistDraft();
    } catch (error) {
      this.aiOnline = false;
      const serviceError: Error = error as Error;
      if (serviceError instanceof RecipeAiServiceError && serviceError.code === 'IDENTITY_REQUIRED') {
        await identityVerificationService.clearIdentity();
        this.clearVerifiedIdentity();
        this.verificationMessage = '华为账号登录已失效，请重新登录';
        this.statusMessage = '';
      } else {
        const reply: string = this.aiErrorMessage(serviceError);
        if (this.hasDraft) {
          this.draftHistory = this.draftHistory.concat([this.currentDraftVersion()]);
          this.latestInstruction = message;
          this.assistantReply = reply;
          this.draftRenderRevision += 1;
          this.rebuildConversationMessages();
          await this.persistDraft();
        } else {
          this.originalText = message;
          this.clarificationTurns = [{ userText: '', assistantText: reply }];
          this.rebuildConversationMessages();
        }
        this.statusMessage = '';
      }
      this.composerText = '';
      this.pendingUserMessage = '';
    } finally {
      this.isWorking = false;
      this.scrollConversationToBottom();
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
      const photoUri: string = await pickRecipePhotoUri(allowCamera);
      if (photoUri.length === 0) {
        this.showPhotoPrompt = true;
        return;
      }
      this.pendingPhotoUri = photoUri;
      this.pendingPhotoTarget = 0;
      this.showPhotoConfirm = true;
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      console.error(`Failed to select recipe photo. Code: ${businessError.code}, message: ${businessError.message}`);
      this.statusMessage = '没有选中照片，菜谱还没有保存';
      this.showPhotoPrompt = true;
    }
  }

  private async confirmPendingPhoto(): Promise<void> {
    if (this.pendingPhotoUri.length === 0) {
      return;
    }
    const photoUri: string = this.pendingPhotoUri;
    const target: number = this.pendingPhotoTarget;
    this.showPhotoConfirm = false;
    this.isWorking = true;
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const photoPath: string = await persistRecipePhoto(context, photoUri);
      this.pendingPhotoUri = '';
      if (target === 0) {
        await this.archiveDraft(photoPath);
      } else {
        await this.applyDetailPhoto(photoPath);
      }
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      console.error(`Failed to persist recipe photo. Code: ${businessError.code}, message: ${businessError.message}`);
      this.statusMessage = target === 0 ?
        '封面没有保存成功，菜谱草稿仍然保留' : '封面没有保存成功，请重试';
      this.showPhotoConfirm = true;
    } finally {
      this.isWorking = false;
    }
  }

  private cancelPendingPhoto(): void {
    const target: number = this.pendingPhotoTarget;
    this.showPhotoConfirm = false;
    this.pendingPhotoUri = '';
    if (target === 0) {
      this.showPhotoPrompt = true;
    }
  }

  private async repickPendingPhoto(): Promise<void> {
    const target: number = this.pendingPhotoTarget;
    this.showPhotoConfirm = false;
    try {
      const photoUri: string = await pickRecipePhotoUri(true);
      if (photoUri.length === 0) {
        this.showPhotoConfirm = true;
        return;
      }
      this.pendingPhotoUri = photoUri;
      this.pendingPhotoTarget = target;
      this.showPhotoConfirm = true;
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      console.error(`Failed to reselect recipe photo. Code: ${businessError.code}, message: ${businessError.message}`);
      this.statusMessage = '没有选中照片，请重试';
      this.showPhotoConfirm = true;
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
    this.questionIds = [];
    this.clarificationTurns = [];
    this.latestInstruction = '';
    this.assistantReply = '';
    this.draftHistory = [];
    this.conversationMessages = [];
    this.conversationMessageRevision += 1;
    this.draftRenderRevision = 0;
    this.draftName = '';
    this.draftSteps = [];
    this.draftIngredients = [];
    this.draftSeasonings = [];
    this.draftExperience = [];
    this.showDraftRecipeDetail = false;
    this.statusMessage = '';
    this.pendingUserMessage = '';
    this.rebuildConversationMessages();
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
    this.editSteps = this.detailSteps.slice();
    this.editStepIds = this.editSteps.map(() => util.generateRandomUUID(true));
    const ingredients: AiRecipeItem[] = this.detailIngredients.map((item: string) => this.parseAiItem(item));
    this.editIngredientNames = ingredients.map((item: AiRecipeItem) => item.name);
    this.editIngredientAmounts = ingredients.map((item: AiRecipeItem) => item.amount);
    this.editIngredientEstimated = ingredients.map((item: AiRecipeItem) => item.isAiEstimated);
    this.editIngredientIds = ingredients.map(() => util.generateRandomUUID(true));
    const seasonings: AiRecipeItem[] = this.detailSeasonings.map((item: string) => this.parseAiItem(item));
    this.editSeasoningNames = seasonings.map((item: AiRecipeItem) => item.name);
    this.editSeasoningAmounts = seasonings.map((item: AiRecipeItem) => item.amount);
    this.editSeasoningEstimated = seasonings.map((item: AiRecipeItem) => item.isAiEstimated);
    this.editSeasoningIds = seasonings.map(() => util.generateRandomUUID(true));
    this.editExperience = this.detailExperience.slice();
    this.editExperienceIds = this.editExperience.map(() => util.generateRandomUUID(true));
    this.editSectionIndex = 0;
    this.editFeedbackMessage = '';
    this.isEditingDetail = true;
    this.statusMessage = '';
  }

  private nonEmptyItems(values: string[]): string[] {
    return values.map((value: string) => value.trim()).filter((value: string) => value.length > 0);
  }

  private combineEditableItems(names: string[], amounts: string[], estimated: boolean[]): string[] {
    const result: string[] = [];
    names.forEach((name: string, index: number) => {
      const cleanName: string = name.trim();
      if (cleanName.length === 0) {
        return;
      }
      result.push(this.formatAiItem({
        name: cleanName,
        amount: index < amounts.length ? amounts[index].trim() : '',
        isAiEstimated: index < estimated.length ? estimated[index] : false
      }));
    });
    return result;
  }

  private setStringItem(values: string[], index: number, value: string): string[] {
    const updated: string[] = values.slice();
    updated[index] = value;
    return updated;
  }

  private setBooleanItem(values: boolean[], index: number, value: boolean): boolean[] {
    const updated: boolean[] = values.slice();
    updated[index] = value;
    return updated;
  }

  private removeStringItem(values: string[], index: number): string[] {
    const updated: string[] = values.slice();
    updated.splice(index, 1);
    return updated;
  }

  private removeBooleanItem(values: boolean[], index: number): boolean[] {
    const updated: boolean[] = values.slice();
    updated.splice(index, 1);
    return updated;
  }

  private moveStringItem(values: string[], from: number, to: number): string[] {
    if (from < 0 || to < 0 || from >= values.length || to >= values.length || from === to) {
      return values;
    }
    const updated: string[] = values.slice();
    const moved: string = updated[from];
    updated.splice(from, 1);
    updated.splice(to, 0, moved);
    return updated;
  }

  private moveBooleanItem(values: boolean[], from: number, to: number): boolean[] {
    if (from < 0 || to < 0 || from >= values.length || to >= values.length || from === to) {
      return values;
    }
    const updated: boolean[] = values.slice();
    const moved: boolean = updated[from];
    updated.splice(from, 1);
    updated.splice(to, 0, moved);
    return updated;
  }

  private addMeasuredItem(kind: number): void {
    if (kind === 0) {
      this.editIngredientNames = this.editIngredientNames.concat(['']);
      this.editIngredientAmounts = this.editIngredientAmounts.concat(['']);
      this.editIngredientEstimated = this.editIngredientEstimated.concat([false]);
      this.editIngredientIds = this.editIngredientIds.concat([util.generateRandomUUID(true)]);
    } else {
      this.editSeasoningNames = this.editSeasoningNames.concat(['']);
      this.editSeasoningAmounts = this.editSeasoningAmounts.concat(['']);
      this.editSeasoningEstimated = this.editSeasoningEstimated.concat([false]);
      this.editSeasoningIds = this.editSeasoningIds.concat([util.generateRandomUUID(true)]);
    }
    this.scrollEditListToBottom(kind, true);
  }

  private scrollEditListToBottom(kind: number, measured: boolean): void {
    setTimeout((): void => {
      if (measured) {
        (kind === 0 ? this.ingredientEditScroller : this.seasoningEditScroller).scrollEdge(Edge.Bottom);
      } else {
        (kind === 0 ? this.stepEditScroller : this.experienceEditScroller).scrollEdge(Edge.Bottom);
      }
    }, 120);
  }

  private measuredItemIndex(id: string, kind: number): number {
    return kind === 0 ? this.editIngredientIds.indexOf(id) : this.editSeasoningIds.indexOf(id);
  }

  private textItemIndex(id: string, kind: number): number {
    return kind === 0 ? this.editStepIds.indexOf(id) : this.editExperienceIds.indexOf(id);
  }

  private removeMeasuredItem(id: string, kind: number): void {
    const index: number = this.measuredItemIndex(id, kind);
    if (index < 0) {
      return;
    }
    if (kind === 0) {
      this.editIngredientNames = this.removeStringItem(this.editIngredientNames, index);
      this.editIngredientAmounts = this.removeStringItem(this.editIngredientAmounts, index);
      this.editIngredientEstimated = this.removeBooleanItem(this.editIngredientEstimated, index);
      this.editIngredientIds = this.removeStringItem(this.editIngredientIds, index);
    } else {
      this.editSeasoningNames = this.removeStringItem(this.editSeasoningNames, index);
      this.editSeasoningAmounts = this.removeStringItem(this.editSeasoningAmounts, index);
      this.editSeasoningEstimated = this.removeBooleanItem(this.editSeasoningEstimated, index);
      this.editSeasoningIds = this.removeStringItem(this.editSeasoningIds, index);
    }
  }

  private updateMeasuredName(value: string, id: string, kind: number): void {
    const index: number = this.measuredItemIndex(id, kind);
    if (index < 0) {
      return;
    }
    if (kind === 0) {
      this.editIngredientNames = this.setStringItem(this.editIngredientNames, index, value);
      this.editIngredientEstimated = this.setBooleanItem(this.editIngredientEstimated, index, false);
    } else {
      this.editSeasoningNames = this.setStringItem(this.editSeasoningNames, index, value);
      this.editSeasoningEstimated = this.setBooleanItem(this.editSeasoningEstimated, index, false);
    }
  }

  private updateMeasuredAmount(value: string, id: string, kind: number): void {
    const index: number = this.measuredItemIndex(id, kind);
    if (index < 0) {
      return;
    }
    if (kind === 0) {
      this.editIngredientAmounts = this.setStringItem(this.editIngredientAmounts, index, value);
      this.editIngredientEstimated = this.setBooleanItem(this.editIngredientEstimated, index, false);
    } else {
      this.editSeasoningAmounts = this.setStringItem(this.editSeasoningAmounts, index, value);
      this.editSeasoningEstimated = this.setBooleanItem(this.editSeasoningEstimated, index, false);
    }
  }

  private chooseMeasuredAmount(value: string, id: string, kind: number): void {
    const index: number = this.measuredItemIndex(id, kind);
    if (index < 0) {
      return;
    }
    this.updateMeasuredAmount(value, id, kind);
    const replacementId: string = util.generateRandomUUID(true);
    if (kind === 0) {
      this.editIngredientIds = this.setStringItem(this.editIngredientIds, index, replacementId);
    } else {
      this.editSeasoningIds = this.setStringItem(this.editSeasoningIds, index, replacementId);
    }
  }

  private commonAmountMenu(id: string, kind: number): MenuElement[] {
    const amounts: string[] = kind === 0 ? INGREDIENT_AMOUNTS : SEASONING_AMOUNTS;
    return amounts.map((amount: string): MenuElement => ({
      value: amount,
      action: (): void => this.chooseMeasuredAmount(amount, id, kind)
    }));
  }

  private addTextItem(kind: number): void {
    if (kind === 0) {
      this.editSteps = this.editSteps.concat(['']);
      this.editStepIds = this.editStepIds.concat([util.generateRandomUUID(true)]);
    } else {
      this.editExperience = this.editExperience.concat(['']);
      this.editExperienceIds = this.editExperienceIds.concat([util.generateRandomUUID(true)]);
    }
    this.scrollEditListToBottom(kind, false);
  }

  private removeTextItem(id: string, kind: number): void {
    const index: number = this.textItemIndex(id, kind);
    if (index < 0) {
      return;
    }
    if (kind === 0) {
      this.editSteps = this.removeStringItem(this.editSteps, index);
      this.editStepIds = this.removeStringItem(this.editStepIds, index);
    } else {
      this.editExperience = this.removeStringItem(this.editExperience, index);
      this.editExperienceIds = this.removeStringItem(this.editExperienceIds, index);
    }
  }

  private updateTextItem(value: string, id: string, kind: number): void {
    const index: number = this.textItemIndex(id, kind);
    if (index < 0) {
      return;
    }
    if (kind === 0) {
      this.editSteps = this.setStringItem(this.editSteps, index, value);
    } else {
      this.editExperience = this.setStringItem(this.editExperience, index, value);
    }
  }

  private moveMeasuredItem(from: number, to: number, kind: number): boolean {
    if (kind === 0) {
      this.editIngredientNames = this.moveStringItem(this.editIngredientNames, from, to);
      this.editIngredientAmounts = this.moveStringItem(this.editIngredientAmounts, from, to);
      this.editIngredientEstimated = this.moveBooleanItem(this.editIngredientEstimated, from, to);
      this.editIngredientIds = this.moveStringItem(this.editIngredientIds, from, to);
    } else {
      this.editSeasoningNames = this.moveStringItem(this.editSeasoningNames, from, to);
      this.editSeasoningAmounts = this.moveStringItem(this.editSeasoningAmounts, from, to);
      this.editSeasoningEstimated = this.moveBooleanItem(this.editSeasoningEstimated, from, to);
      this.editSeasoningIds = this.moveStringItem(this.editSeasoningIds, from, to);
    }
    return true;
  }

  private moveTextItem(from: number, to: number, kind: number): boolean {
    if (kind === 0) {
      this.editSteps = this.moveStringItem(this.editSteps, from, to);
      this.editStepIds = this.moveStringItem(this.editStepIds, from, to);
    } else {
      this.editExperience = this.moveStringItem(this.editExperience, from, to);
      this.editExperienceIds = this.moveStringItem(this.editExperienceIds, from, to);
    }
    return true;
  }

  private measuredItemLabel(index: number, kind: number): string {
    if (kind === 0) {
      return index >= 0 && index < this.editIngredientNames.length ? this.editIngredientNames[index] : '食材';
    }
    return index >= 0 && index < this.editSeasoningNames.length ? this.editSeasoningNames[index] : '调料';
  }

  private textItemLabel(index: number, kind: number): string {
    if (kind === 0) {
      return index >= 0 && index < this.editSteps.length ? this.editSteps[index] : '制作步骤';
    }
    return index >= 0 && index < this.editExperience.length ? this.editExperience[index] : '经验建议';
  }

  private normalizedDropIndex(itemIndex: number, insertIndex: number, length: number): number {
    if (length === 0 || itemIndex < 0 || itemIndex >= length || insertIndex < 0) {
      return -1;
    }
    return Math.max(0, Math.min(insertIndex, length - 1));
  }

  private dropMeasuredItem(itemIndex: number, insertIndex: number, kind: number): void {
    const length: number = kind === 0 ? this.editIngredientIds.length : this.editSeasoningIds.length;
    const target: number = this.normalizedDropIndex(itemIndex, insertIndex, length);
    if (target >= 0) {
      this.moveMeasuredItem(itemIndex, target, kind);
    }
  }

  private dropTextItem(itemIndex: number, insertIndex: number, kind: number): void {
    const length: number = kind === 0 ? this.editStepIds.length : this.editExperienceIds.length;
    const target: number = this.normalizedDropIndex(itemIndex, insertIndex, length);
    if (target >= 0) {
      this.moveTextItem(itemIndex, target, kind);
    }
  }

  private liveMoveMeasuredItem(insertIndex: number, kind: number): void {
    const current: number = this.measuredItemIndex(this.editDraggedId, kind);
    const length: number = kind === 0 ? this.editIngredientIds.length : this.editSeasoningIds.length;
    const target: number = this.normalizedDropIndex(current, insertIndex, length);
    if (current < 0 || target < 0 || current === target) {
      return;
    }
    animateTo({ duration: 160, curve: Curve.Friction }, (): void => {
      this.moveMeasuredItem(current, target, kind);
    });
  }

  private liveMoveTextItem(insertIndex: number, kind: number): void {
    const current: number = this.textItemIndex(this.editDraggedId, kind);
    const length: number = kind === 0 ? this.editStepIds.length : this.editExperienceIds.length;
    const target: number = this.normalizedDropIndex(current, insertIndex, length);
    if (current < 0 || target < 0 || current === target) {
      return;
    }
    animateTo({ duration: 160, curve: Curve.Friction }, (): void => {
      this.moveTextItem(current, target, kind);
    });
  }

  private async saveDetailChanges(): Promise<void> {
    const steps: string[] = this.nonEmptyItems(this.editSteps);
    if (this.repository === null || this.editName.trim().length === 0 || steps.length === 0) {
      this.statusMessage = '菜名和制作步骤不能为空';
      return;
    }
    const updated: RecipeRecord = {
      id: this.detailId,
      name: this.editName.trim(),
      steps,
      ingredients: this.combineEditableItems(
        this.editIngredientNames, this.editIngredientAmounts, this.editIngredientEstimated),
      seasonings: this.combineEditableItems(
        this.editSeasoningNames, this.editSeasoningAmounts, this.editSeasoningEstimated),
      experience: this.nonEmptyItems(this.editExperience),
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
      const photoUri: string = await pickRecipePhotoUri(true);
      if (photoUri.length > 0) {
        this.pendingPhotoUri = photoUri;
        this.pendingPhotoTarget = 1;
        this.showPhotoConfirm = true;
      }
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      console.error(`Failed to select replacement photo. Code: ${businessError.code}, message: ${businessError.message}`);
      this.statusMessage = '没有选中照片，请重试';
    }
  }

  private async applyDetailPhoto(photoPath: string): Promise<void> {
    if (this.repository === null || this.detailId.length === 0) {
      throw new Error('Recipe repository or detail is unavailable');
    }
    const updated: RecipeRecord = {
      id: this.detailId,
      name: this.detailName,
      steps: this.detailSteps,
      ingredients: this.detailIngredients,
      seasonings: this.detailSeasonings,
      experience: this.detailExperience,
      photoPath,
      originalText: this.detailOriginalText,
      createdAt: this.detailCreatedAt,
      updatedAt: Date.now()
    };
    await this.repository.update(updated);
    await this.refreshRecipes();
    this.openRecipe(updated);
    this.statusMessage = '';
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
    setTimeout(() => this.finalizeDelete(deletedId), 2000);
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

  private formatDateTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }
    const date: Date = new Date(timestamp);
    const hours: string = `${date.getHours()}`.padStart(2, '0');
    const minutes: string = `${date.getMinutes()}`.padStart(2, '0');
    return `${this.formatDate(timestamp)} ${hours}:${minutes}`;
  }

  private accountDisplayName(): string {
    return this.verifiedDisplayName.length > 0 ? this.verifiedDisplayName : '华为账号用户';
  }

  private accountInitial(): string {
    const value: string = this.accountDisplayName();
    return value.length > 0 ? value.slice(0, 1) : '华';
  }

  private cleanEstimate(item: string): string {
    return item.replace('（AI估算）', '');
  }

  private draftIngredientSummary(): string {
    const names: string[] = this.draftIngredients
      .map((item: string) => this.parseAiItem(item).name)
      .filter((name: string) => name.length > 0);
    if (names.length === 0) {
      return '暂未记录食材';
    }
    const visible: string = names.slice(0, 3).join('、');
    return names.length > 3 ? `${visible} 等 ${names.length} 种` : visible;
  }

  @Builder
  private AssistantAvatar() {
    Stack() {
      Image($r('app.media.startIcon'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
    .width(32)
    .height(32)
    .borderRadius(10)
    .clip(true)
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
  private ThinkingBubble() {
    Row({ space: 10 }) {
      this.AssistantAvatar()
      Row({ space: 9 }) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(JADE)
        Text('正在整理')
          .fontSize(15)
          .fontColor(INK)
      }
      .padding({ left: 14, right: 16, top: 12, bottom: 12 })
      .backgroundColor(CARD)
      .borderRadius({ topLeft: 4, topRight: 16, bottomLeft: 16, bottomRight: 16 })
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
  private DraftTextList(title: string, kind: number) {
    Column({ space: 5 }) {
      Text(title)
        .width('100%')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(JADE)
        .letterSpacing(0.5)
      if ((kind === 0 && this.draftIngredients.length === 0) ||
        (kind === 1 && this.draftSeasonings.length === 0) ||
        (kind === 2 && this.draftExperience.length === 0)) {
        Text('暂未提到')
          .width('100%')
          .fontSize(13)
          .fontColor(MUTED)
          .padding({ top: 6, bottom: 6 })
      } else {
        if (kind === 0) {
          ForEach(this.draftIngredients, (item: string) => {
            this.EstimateItem(item)
          }, (item: string, index: number) => `${index}-${item}`)
        } else if (kind === 1) {
          ForEach(this.draftSeasonings, (item: string) => {
            this.EstimateItem(item)
          }, (item: string, index: number) => `${index}-${item}`)
        } else {
          ForEach(this.draftExperience, (item: string) => {
            this.EstimateItem(item)
          }, (item: string, index: number) => `${index}-${item}`)
        }
      }
    }
    .width('100%')
  }

  @Builder
  private DraftRecipeFullCard() {
    Column({ space: 16 }) {
        Row() {
          Column({ space: 4 }) {
            Text('菜谱内容由 AI 生成')
              .width('100%')
              .fontSize(11)
              .fontColor(MUTED)
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
          Text('·')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(MUTED)
          Text(`${this.draftSteps.length} 步`)
            .fontSize(12)
            .fontColor(MUTED)
        }
        .width('100%')

        Divider().color(LINE)
        this.DraftTextList('食材及用量', 0)
        this.DraftTextList('调料及用量', 1)

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

        this.DraftTextList('经验建议', 2)

    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 18 })
    .backgroundColor(CARD)
    .borderRadius(20)
    .border({ width: 1, color: '#D7DFDA' })
    .shadow({ radius: 14, color: '#12000000', offsetY: 4 })
    .id(`latest-${this.draftRenderRevision}`)
  }

  @Builder
  private DraftRecipeCompactCard() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text(this.draftName)
            .width('100%')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.draftIngredientSummary())
            .width('100%')
            .fontSize(12)
            .fontColor(MUTED)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Column({ space: 4 }) {
          Text(`${this.draftSteps.length}步`)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(JADE)
        }
        .width(54)
        .height(54)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(JADE_SOFT)
        .borderRadius(15)
      }
      .width('100%')
      Row({ space: 10 }) {
        Button('展开菜谱')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(JADE)
          .backgroundColor(JADE_SOFT)
          .borderRadius(12)
          .onClick(() => this.showDraftRecipeDetail = true)
        Button('完成菜谱')
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(this.canFinishDraft() ? CHILI : '#AEB6B1')
          .borderRadius(12)
          .enabled(this.canFinishDraft())
          .onClick(() => this.finishDraft())
      }
      .width('100%')
    }
    .width('100%')
    .padding(15)
    .backgroundColor(CARD)
    .border({ width: 1, color: '#D7DFDA' })
    .borderRadius(17)
    .shadow({ radius: 10, color: '#10000000', offsetY: 3 })
    .id(`latest-compact-${this.draftRenderRevision}`)
  }

  @Builder
  private DraftRecipeDetailPage() {
    Column() {
      Row({ space: 10 }) {
        Text('完整菜谱')
          .layoutWeight(1)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(JADE)
        Button('回到对话')
          .height(36)
          .fontSize(12)
          .fontColor(JADE)
          .backgroundColor(JADE_SOFT)
          .borderRadius(11)
          .onClick(() => this.returnToConversation())
        Button('完成菜谱')
          .height(36)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(this.canFinishDraft() ? CHILI : '#AEB6B1')
          .borderRadius(11)
          .enabled(this.canFinishDraft())
          .onClick(() => this.finishDraft())
      }
      .width('100%')
      .height(62)
      .padding({ left: 16, right: 16 })
      .backgroundColor(CARD)
      .border({ width: { bottom: 1 }, color: LINE })

      Scroll() {
        Column() {
          this.DraftRecipeFullCard()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 18 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      Column() {
        Row({ space: 10 }) {
          TextArea({ text: this.composerText, placeholder: '继续告诉我怎么改…' })
            .layoutWeight(1)
            .constraintSize({ minHeight: 52, maxHeight: 112 })
            .maxLines(4)
            .fontSize(15)
            .lineHeight(21)
            .fontColor(INK)
            .placeholderColor(MUTED)
            .caretColor(JADE)
            .backgroundColor('#EDF1EE')
            .borderRadius(16)
            .padding({ left: 13, right: 13, top: 9, bottom: 9 })
            .enterKeyType(EnterKeyType.Send)
            .barState(BarState.Off)
            .onSubmit(() => {
              this.returnToConversation();
              this.sendMessage();
            })
            .onChange((value: string) => {
              this.composerText = value;
              this.statusMessage = '';
            })
          Button('↑', { type: ButtonType.Circle })
            .width(46)
            .height(46)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .backgroundColor(this.composerText.trim().length > 0 ? JADE : '#AEB6B1')
            .enabled(this.composerText.trim().length > 0 && !this.isWorking)
            .onClick(() => {
              this.returnToConversation();
              this.sendMessage();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 9, bottom: 9 })
      .backgroundColor(CARD)
      .border({ width: { top: 1 }, color: LINE })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
  }

  @Builder
  private IdentityVerificationPage() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('厨房主理人')
            .width('100%')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(JADE)
          Text('登录后使用 AI 整理功能')
            .width('100%')
            .fontSize(12)
            .fontColor(MUTED)
        }
        .layoutWeight(1)
        Text('账号登录')
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor(JADE)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(JADE_SOFT)
          .borderRadius(14)
      }
      .width('100%')
      .height(68)
      .padding({ left: 18, right: 18 })
      .backgroundColor(CARD)

      Scroll() {
        Column({ space: 22 }) {
          Column({ space: 12 }) {
            Stack() {
              Image($r('app.media.startIcon'))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
            }
            .width(62)
            .height(62)
            .borderRadius(31)
            .clip(true)
            Text('登录后开始整理菜谱')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(INK)
            Text('使用华为账号登录后，即可把做菜过程整理成自己的菜谱。')
              .width('100%')
              .fontSize(13)
              .lineHeight(20)
              .fontColor(MUTED)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)

          Column({ space: 16 }) {
            Row({ space: 8 }) {
              Checkbox({ name: 'aiComplianceTerms', group: 'identityVerification' })
                .select(this.acceptedAiTerms)
                .selectedColor(JADE)
                .onChange((value: boolean) => {
                  this.updateHuaweiAgreement(value);
                })
              Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
                Text('我已阅读并同意')
                  .fontSize(12)
                  .lineHeight(20)
                  .fontColor(MUTED)
                  .margin({ right: 5, bottom: 2 })
                Text('《AI 服务规则》')
                  .fontSize(12)
                  .lineHeight(20)
                  .fontColor(JADE)
                  .fontWeight(FontWeight.Medium)
                  .margin({ right: 5, bottom: 2 })
                  .onClick(() => this.loginPolicyDetailKind = 1)
                Text('和')
                  .fontSize(12)
                  .lineHeight(20)
                  .fontColor(MUTED)
                  .margin({ right: 5, bottom: 2 })
                Text('《隐私政策》')
                  .fontSize(12)
                  .lineHeight(20)
                  .fontColor(JADE)
                  .fontWeight(FontWeight.Medium)
                  .margin({ bottom: 2 })
                  .onClick(() => this.loginPolicyDetailKind = 2)
              }
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            LoginWithHuaweiIDButton({
              params: {
                style: loginComponentManager.Style.BUTTON_RED,
                borderRadius: 14,
                loginType: loginComponentManager.LoginType.ID,
                textAndIconStyle: true,
                verifyPhoneNumber: false,
                supportDarkMode: true,
                extraStyle: {
                  buttonStyle: new loginComponentManager.ButtonStyle().loadingStyle({ show: true })
                }
              },
              controller: this.huaweiLoginController
            })
              .width('100%')
              .height(48)

            if (this.verificationMessage.length > 0) {
              Text(this.verificationMessage)
                .width('100%')
                .fontSize(12)
                .lineHeight(18)
                .fontColor(this.verificationMessage.startsWith('正在') ? JADE : CHILI)
                .padding({ left: 11, right: 11, top: 8, bottom: 8 })
                .backgroundColor(this.verificationMessage.startsWith('正在') ? '#EEF5F1' : '#FBEDE9')
                .borderRadius(10)
            }

            Text('登录信息仅用于账号验证与会话维持。')
              .width('100%')
              .fontSize(12)
              .lineHeight(18)
              .fontColor(MUTED)
          }
          .width('100%')
          .padding(18)
          .backgroundColor(CARD)
          .border({ width: 1, color: LINE })
          .borderRadius(20)

        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 24, bottom: 28 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
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
          Text(this.isWorking ? 'AI 正在整理…' :
            (this.hasDraft ? '菜谱内容由 AI 生成' : '把做成功的味道记下来'))
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
          Text(this.aiOnline ? 'AI 服务可用' : 'AI 待连接')
            .fontSize(11)
            .fontColor(this.aiOnline ? JADE : MUTED)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(this.aiOnline ? JADE_SOFT : '#E8ECE9')
            .borderRadius(14)
        }
      }
      .width('100%')
      .height(68)
      .padding({ left: 18, right: 18 })
      .backgroundColor(CARD)

      Scroll(this.conversationScroller) {
        Column({ space: 14 }) {
          ForEach(this.conversationMessages, (message: ConversationMessage) => {
            if (message.role === 1) {
              this.UserBubble(message.text)
            } else {
              this.AssistantBubble(message.text)
            }
          }, (message: ConversationMessage) => message.id)

          if (this.hasDraft) {
            this.DraftRecipeCompactCard()
          }

          if (this.pendingUserMessage.length > 0) {
            this.UserBubble(this.pendingUserMessage)
            this.ThinkingBubble()
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
        .id(`conversation-${this.conversationMessageRevision}`)
        .padding({ left: 16, right: 16, top: 18, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      Column() {
        Row({ space: 10 }) {
          TextArea({
            text: this.composerText,
            placeholder: this.hasDraft ? '告诉我哪里要改…' :
              (this.hasQuestion ? '补充关键信息…' : '描述这道菜的做法…')
          })
            .layoutWeight(1)
            .constraintSize({ minHeight: 52, maxHeight: 112 })
            .maxLines(4)
            .fontSize(15)
            .lineHeight(21)
            .fontColor(INK)
            .placeholderColor(MUTED)
            .caretColor(JADE)
            .backgroundColor('#EDF1EE')
            .borderRadius(16)
            .padding({ left: 13, right: 13, top: 9, bottom: 9 })
            .enterKeyType(EnterKeyType.Send)
            .barState(BarState.Off)
            .onSubmit(() => this.sendMessage())
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
        .alignItems(VerticalAlign.Bottom)

      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
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
  private RecipeGridCard(recipe: RecipeRecord) {
    Column() {
      Stack() {
        if (recipe.photoPath.length > 0) {
          Image(recipe.photoPath)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Text(recipe.name.length > 0 ? recipe.name.slice(0, 1) : '菜')
            .fontSize(40)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
      }
      .width('100%')
      .height(126)
      .backgroundColor(JADE)

      Text(recipe.name)
        .width('100%')
        .height(48)
        .padding({ left: 11, right: 11 })
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .backgroundColor(recipe.id === this.highlightedRecipeId ? '#E4EFE8' : CARD)
    .border({
      width: recipe.id === this.highlightedRecipeId ? 2 : 1,
      color: recipe.id === this.highlightedRecipeId ? '#79A68F' : LINE
    })
    .borderRadius(16)
    .clip(true)
    .onClick(() => this.openRecipe(recipe))
  }

  @Builder
  private RecipeLayoutToggle() {
    Row() {
      Text('列表')
        .width(50)
        .height(38)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.recipeLayoutMode === 0 ? '#FFFFFF' : JADE)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.recipeLayoutMode === 0 ? JADE : '#00000000')
        .borderRadius(10)
        .accessibilityText('按条目显示')
        .onClick(() => this.recipeLayoutMode = 0)
      Text('双列')
        .width(50)
        .height(38)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.recipeLayoutMode === 1 ? '#FFFFFF' : JADE)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.recipeLayoutMode === 1 ? JADE : '#00000000')
        .borderRadius(10)
        .accessibilityText('按双列卡片显示')
        .onClick(() => this.recipeLayoutMode = 1)
    }
    .padding(3)
    .backgroundColor(JADE_SOFT)
    .borderRadius(13)
  }

  @Builder
  private RecipeLibraryPage() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('我的菜谱夹')
            .width('100%')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(JADE)
          Text(`${this.recipes.length} 道家常味道`)
            .width('100%')
            .fontSize(12)
            .fontColor(MUTED)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        this.RecipeLayoutToggle()
      }
      .width('100%')
      .height(68)
      .padding({ left: 18, right: 18 })
      .backgroundColor(CARD)

      Column({ space: 14 }) {
        Search({ value: this.searchText, placeholder: '搜菜名、食材或调料' })
          .width('100%')
          .height(44)
          .fontColor(INK)
          .placeholderColor(MUTED)
          .caretStyle({ width: 2, color: JADE })
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
        } else if (this.recipeLayoutMode === 0) {
          List({ space: 10 }) {
            ForEach(this.visibleRecipes, (recipe: RecipeRecord) => {
              ListItem() {
                this.RecipeListCard(recipe)
              }
            }, (recipe: RecipeRecord) => `${recipe.id}-${recipe.updatedAt}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else {
          Grid() {
            ForEach(this.visibleRecipes, (recipe: RecipeRecord) => {
              GridItem() {
                this.RecipeGridCard(recipe)
              }
            }, (recipe: RecipeRecord) => `${recipe.id}-${recipe.updatedAt}`)
          }
          .width('100%')
          .layoutWeight(1)
          .columnsTemplate('1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .scrollBar(BarState.Off)
        }
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
  }

  @Builder
  private DetailListItem(item: string, index: number, numbered: boolean) {
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
        Circle()
          .width(6)
          .height(6)
          .fill(CHILI)
          .margin({ top: 8 })
      }
      Text(this.cleanEstimate(item))
        .layoutWeight(1)
        .fontSize(15)
        .lineHeight(22)
        .fontColor(INK)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private DetailListSection(title: string, kind: number, numbered: boolean) {
    Column({ space: 10 }) {
      Text(title)
        .width('100%')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(JADE)
      if ((kind === 0 && this.detailIngredients.length === 0) ||
        (kind === 1 && this.detailSeasonings.length === 0) ||
        (kind === 2 && this.detailSteps.length === 0) ||
        (kind === 3 && this.detailExperience.length === 0)) {
        Text('未记录')
          .width('100%')
          .fontSize(14)
          .fontColor(MUTED)
      } else {
        if (kind === 0) {
          ForEach(this.detailIngredients, (item: string, index: number) => {
            this.DetailListItem(item, index, numbered)
          }, (item: string, index: number) => `${index}-${item}`)
        } else if (kind === 1) {
          ForEach(this.detailSeasonings, (item: string, index: number) => {
            this.DetailListItem(item, index, numbered)
          }, (item: string, index: number) => `${index}-${item}`)
        } else if (kind === 2) {
          ForEach(this.detailSteps, (item: string, index: number) => {
            this.DetailListItem(item, index, numbered)
          }, (item: string, index: number) => `${index}-${item}`)
        } else {
          ForEach(this.detailExperience, (item: string, index: number) => {
            this.DetailListItem(item, index, numbered)
          }, (item: string, index: number) => `${index}-${item}`)
        }
      }
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  @Builder
  private DetailEditPage() {
    Column() {
      Row({ space: 10 }) {
        Button('‹')
          .width(40)
          .height(40)
          .fontSize(28)
          .fontColor(JADE)
          .backgroundColor(JADE_SOFT)
          .borderRadius(14)
          .onClick(() => this.isEditingDetail = false)
        Column({ space: 2 }) {
          Text('编辑菜谱')
            .width('100%')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(JADE)
          Text('左右滑动切换内容，长按条目可排序')
            .width('100%')
            .fontSize(12)
            .fontColor(MUTED)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 10 })

      Column({ space: 8 }) {
        Text('菜名')
          .width('100%')
          .fontSize(12)
          .fontColor(MUTED)
        TextInput({ text: this.editName, placeholder: '输入菜名' })
          .width('100%')
          .height(48)
          .fontSize(18)
          .fontColor(INK)
          .placeholderColor(MUTED)
          .caretColor(JADE)
          .backgroundColor(CARD)
          .border({ width: 1, color: LINE })
          .borderRadius(14)
          .onChange((value: string) => this.editName = value)
        if (this.statusMessage.length > 0) {
          Text(this.statusMessage)
            .width('100%')
            .fontSize(12)
            .fontColor(CHILI)
        }
        if (this.editFeedbackMessage.length > 0) {
          Text(this.editFeedbackMessage)
            .width('100%')
            .fontSize(12)
            .fontColor(JADE)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 10 })

      Row({ space: 4 }) {
        this.EditSectionTab('食材', 0)
        this.EditSectionTab('调料', 1)
        this.EditSectionTab('步骤', 2)
        this.EditSectionTab('经验', 3)
      }
      .width('100%')
      .height(44)
      .padding(4)
      .margin({ left: 16, right: 16, bottom: 10 })
      .backgroundColor('#E7ECE8')
      .borderRadius(14)

      Swiper() {
        this.MeasuredEditSection('食材及用量', '食材', 0)
        this.MeasuredEditSection('调料及用量', '调料', 1)
        this.TextItemEditSection('制作步骤', '步骤', 0)
        this.TextItemEditSection('经验建议', '建议', 1)
      }
      .index(this.editSectionIndex)
      .indicator(false)
      .loop(false)
      .layoutWeight(1)
      .width('100%')
      .onChange((index: number) => this.editSectionIndex = index)

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(48)
          .fontColor(JADE)
          .backgroundColor(JADE_SOFT)
          .borderRadius(16)
          .onClick(() => this.isEditingDetail = false)
        Button('保存修改')
          .layoutWeight(1)
          .height(48)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .backgroundColor(JADE)
          .borderRadius(16)
          .onClick(() => this.saveDetailChanges())
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 12 })
      .backgroundColor(CARD)
      .border({ width: { top: 1 }, color: LINE })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
  }

  @Builder
  private EditSectionTab(label: string, index: number) {
    Text(label)
      .layoutWeight(1)
      .height(36)
      .fontSize(13)
      .fontWeight(this.editSectionIndex === index ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(this.editSectionIndex === index ? JADE : MUTED)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.editSectionIndex === index ? CARD : '#00000000')
      .borderRadius(11)
      .shadow(this.editSectionIndex === index ? { radius: 5, color: '#12000000', offsetY: 2 } :
        { radius: 0, color: '#00000000', offsetY: 0 })
      .onClick(() => this.editSectionIndex = index)
  }

  @Builder
  private EditSectionHeader(title: string, addLabel: string, kind: number, measured: boolean) {
    Row() {
      Text(title)
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(JADE)
      Button(`＋ ${addLabel}`)
        .height(34)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(JADE)
        .backgroundColor(JADE_SOFT)
        .borderRadius(11)
        .onClick(() => {
          if (measured) {
            this.addMeasuredItem(kind);
          } else {
            this.addTextItem(kind);
          }
        })
    }
    .width('100%')
  }

  @Builder
  private MeasuredEditItem(
    id: string, name: string, amount: string, estimated: boolean, index: number, kind: number) {
    Row({ space: 6 }) {
      Text('≡')
        .width(24)
        .fontSize(20)
        .fontColor('#8B9791')
        .textAlign(TextAlign.Center)
        .accessibilityText(`拖动第 ${index + 1} 项排序`)
      TextInput({ text: name, placeholder: kind === 0 ? '食材名称' : '调料名称' })
        .layoutWeight(1)
        .height(42)
        .fontSize(14)
        .fontColor(INK)
        .placeholderColor(MUTED)
        .caretColor(JADE)
        .backgroundColor('#F3F6F3')
        .borderRadius(10)
        .padding({ left: 10, right: 8 })
        .onChange((value: string) => this.updateMeasuredName(value, id, kind))
      Row() {
        TextInput({ text: amount, placeholder: '用量' })
          .layoutWeight(1)
          .height(42)
          .fontSize(13)
          .fontColor(INK)
          .placeholderColor(MUTED)
          .caretColor(JADE)
          .backgroundColor('#00000000')
          .padding({ left: 9, right: 2 })
          .onChange((value: string) => this.updateMeasuredAmount(value, id, kind))
        Text('▼')
          .width(30)
          .height(42)
          .fontSize(9)
          .fontColor(JADE)
          .textAlign(TextAlign.Center)
          .backgroundColor(JADE_SOFT)
          .borderRadius({ topLeft: 0, topRight: 10, bottomLeft: 0, bottomRight: 10 })
          .accessibilityText(kind === 0 ? '选择常用食材用量' : '选择常用调料用量')
          .bindMenu(this.commonAmountMenu(id, kind))
      }
      .width(132)
      .height(42)
      .backgroundColor('#F3F6F3')
      .borderRadius(10)
      .clip(true)
      Button('×', { type: ButtonType.Circle })
        .width(32)
        .height(32)
        .fontSize(17)
        .fontColor('#A44332')
        .backgroundColor('#F8E7E3')
        .accessibilityText(`删除第 ${index + 1} 项`)
        .onClick(() => this.removeMeasuredItem(id, kind))
    }
    .width('100%')
    .height(58)
    .padding({ left: 8, right: 8 })
    .backgroundColor(CARD)
    .border({ width: 1, color: LINE })
    .borderRadius(14)
  }

  @Builder
  private EditDragPreview() {
    Row({ space: 7 }) {
      Text('≡')
        .width(24)
        .fontSize(20)
        .fontColor('#8A938E')
      Text(this.editDragPreviewText.length > 0 ? this.editDragPreviewText : '调整顺序')
        .layoutWeight(1)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.editDragPreviewMeasured) {
        Text(this.editDragPreviewAmount.length > 0 ? this.editDragPreviewAmount : '用量')
          .width(104)
          .height(40)
          .padding({ left: 10, right: 10 })
          .fontSize(13)
          .fontColor(INK)
          .backgroundColor('#F3F6F3')
          .borderRadius(9)
      }
    }
    .width(360)
    .height(62)
    .padding({ left: 10, right: 10 })
    .backgroundColor(CARD)
    .border({ width: 1, color: '#B8C9C0' })
    .borderRadius(14)
    .shadow({ radius: 20, color: '#40000000', offsetY: 9 })
    .scale({ x: 1.03, y: 1.03 })
  }

  @Builder
  private MeasuredEditSection(title: string, addLabel: string, kind: number) {
    Column({ space: 10 }) {
      this.EditSectionHeader(title, `添加${addLabel}`, kind, true)
      if ((kind === 0 && this.editIngredientIds.length === 0) ||
        (kind === 1 && this.editSeasoningIds.length === 0)) {
        Text(`还没有${addLabel}，可按右上角添加`)
          .width('100%')
          .fontSize(13)
          .fontColor(MUTED)
          .padding(14)
          .backgroundColor('#E9EFEB')
          .borderRadius(12)
      } else {
        List({ space: 8, scroller: kind === 0 ? this.ingredientEditScroller : this.seasoningEditScroller }) {
          if (kind === 0) {
            ForEach(this.editIngredientIds, (id: string, index: number) => {
              ListItem() {
                this.MeasuredEditItem(
                  id,
                  index < this.editIngredientNames.length ? this.editIngredientNames[index] : '',
                  index < this.editIngredientAmounts.length ? this.editIngredientAmounts[index] : '',
                  index < this.editIngredientEstimated.length ? this.editIngredientEstimated[index] : false,
                  index,
                  kind)
              }
            }, (id: string) => id)
          } else {
            ForEach(this.editSeasoningIds, (id: string, index: number) => {
              ListItem() {
                this.MeasuredEditItem(
                  id,
                  index < this.editSeasoningNames.length ? this.editSeasoningNames[index] : '',
                  index < this.editSeasoningAmounts.length ? this.editSeasoningAmounts[index] : '',
                  index < this.editSeasoningEstimated.length ? this.editSeasoningEstimated[index] : false,
                  index,
                  kind)
              }
            }, (id: string) => id)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .onItemMove((_from: number, _to: number): boolean => true)
        .onItemDragStart((_event: ItemDragInfo, itemIndex: number): CustomBuilder => {
          const ids: string[] = kind === 0 ? this.editIngredientIds : this.editSeasoningIds;
          const amounts: string[] = kind === 0 ? this.editIngredientAmounts : this.editSeasoningAmounts;
          this.editDraggedId = itemIndex >= 0 && itemIndex < ids.length ? ids[itemIndex] : '';
          this.editDragPreviewText = this.measuredItemLabel(itemIndex, kind);
          this.editDragPreviewAmount = itemIndex >= 0 && itemIndex < amounts.length ? amounts[itemIndex] : '';
          this.editDragPreviewMeasured = true;
          this.editFeedbackMessage = `正在移动“${this.editDragPreviewText}”`;
          return this.EditDragPreview;
        })
        .onItemDragMove((_event: ItemDragInfo, _itemIndex: number, insertIndex: number) => {
          this.liveMoveMeasuredItem(insertIndex, kind);
          this.editFeedbackMessage = '拖到合适位置后松手';
        })
        .onItemDrop((_event: ItemDragInfo, _itemIndex: number, _insertIndex: number, _isSuccess: boolean) => {
          if (this.editDraggedId.length > 0) {
            this.editFeedbackMessage = '顺序已调整';
          }
          this.editDraggedId = '';
          this.editDragPreviewMeasured = false;
          this.editDragPreviewAmount = '';
        })
      }
      Text('≡  长按任意条目拖动排序')
        .width('100%')
        .fontSize(11)
        .fontColor(MUTED)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .backgroundColor(CARD)
    .borderRadius({ topLeft: 20, topRight: 20, bottomLeft: 0, bottomRight: 0 })
  }

  @Builder
  private TextEditItem(id: string, text: string, index: number, kind: number) {
    Row({ space: 10 }) {
      Text('≡')
        .width(24)
        .fontSize(20)
        .fontColor('#9AA39E')
        .textAlign(TextAlign.Center)
      TextArea({
        text,
        placeholder: kind === 0 ? `第 ${index + 1} 步怎么做` : '记录一条下次还想记得的经验'
      })
        .layoutWeight(1)
        .constraintSize({ minHeight: 46, maxHeight: kind === 0 ? 142 : 116 })
        .maxLines(kind === 0 ? 6 : 5)
        .fontSize(14)
        .lineHeight(21)
        .fontColor(INK)
        .placeholderColor(MUTED)
        .caretColor(JADE)
        .backgroundColor('#F3F6F3')
        .borderRadius(11)
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .onChange((value: string) => this.updateTextItem(value, id, kind))
      Button('×', { type: ButtonType.Circle })
        .width(34)
        .height(34)
        .fontSize(18)
        .fontColor('#A44332')
        .backgroundColor('#F8E7E3')
        .onClick(() => this.removeTextItem(id, kind))
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 12, right: 12, top: 9, bottom: 9 })
    .backgroundColor(CARD)
    .border({ width: 1, color: LINE })
    .borderRadius(16)
  }

  @Builder
  private TextItemEditSection(title: string, addLabel: string, kind: number) {
    Column({ space: 10 }) {
      this.EditSectionHeader(title, `添加${addLabel}`, kind, false)
      if ((kind === 0 && this.editStepIds.length === 0) ||
        (kind === 1 && this.editExperienceIds.length === 0)) {
        Text(kind === 0 ? '至少添加一个制作步骤' : '没有经验建议也可以保存')
          .width('100%')
          .fontSize(13)
          .fontColor(MUTED)
          .padding(14)
          .backgroundColor('#E9EFEB')
          .borderRadius(12)
      } else {
        List({ space: 10, scroller: kind === 0 ? this.stepEditScroller : this.experienceEditScroller }) {
          if (kind === 0) {
            ForEach(this.editStepIds, (id: string, index: number) => {
              ListItem() {
                this.TextEditItem(
                  id,
                  index < this.editSteps.length ? this.editSteps[index] : '',
                  index,
                  kind)
              }
            }, (id: string) => id)
          } else {
            ForEach(this.editExperienceIds, (id: string, index: number) => {
              ListItem() {
                this.TextEditItem(
                  id,
                  index < this.editExperience.length ? this.editExperience[index] : '',
                  index,
                  kind)
              }
            }, (id: string) => id)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .onItemMove((_from: number, _to: number): boolean => true)
        .onItemDragStart((_event: ItemDragInfo, itemIndex: number): CustomBuilder => {
          const ids: string[] = kind === 0 ? this.editStepIds : this.editExperienceIds;
          this.editDraggedId = itemIndex >= 0 && itemIndex < ids.length ? ids[itemIndex] : '';
          this.editDragPreviewText = this.textItemLabel(itemIndex, kind);
          this.editDragPreviewAmount = '';
          this.editDragPreviewMeasured = false;
          this.editFeedbackMessage = `正在移动“${this.editDragPreviewText}”`;
          return this.EditDragPreview;
        })
        .onItemDragMove((_event: ItemDragInfo, _itemIndex: number, insertIndex: number) => {
          this.liveMoveTextItem(insertIndex, kind);
          this.editFeedbackMessage = '拖到合适位置后松手';
        })
        .onItemDrop((_event: ItemDragInfo, _itemIndex: number, _insertIndex: number, _isSuccess: boolean) => {
          if (this.editDraggedId.length > 0) {
            this.editFeedbackMessage = '顺序已调整';
          }
          this.editDraggedId = '';
          this.editDragPreviewMeasured = false;
          this.editDragPreviewAmount = '';
        })
      }
      Text('≡  长按任意条目拖动排序')
        .width('100%')
        .fontSize(11)
        .fontColor(MUTED)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
    .backgroundColor(CARD)
    .borderRadius({ topLeft: 20, topRight: 20, bottomLeft: 0, bottomRight: 0 })
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
              this.DetailListSection('食材及用量', 0, false)
              Divider().color(LINE)
              this.DetailListSection('调料及用量', 1, false)
              Divider().color(LINE)
              this.DetailListSection('制作步骤', 2, true)
              Divider().color(LINE)
              this.DetailListSection('经验建议', 3, false)
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
  private ProfileLinkRow(title: string, summary: string, kind: number) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(title)
          .width('100%')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(INK)
        Text(summary)
          .width('100%')
          .fontSize(12)
          .fontColor(MUTED)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Text('›')
        .fontSize(24)
        .fontColor('#8A938E')
    }
    .width('100%')
    .height(68)
    .padding({ left: 16, right: 14 })
    .onClick(() => this.profileDetailKind = kind)
  }

  private profileDetailTitle(): string {
    if (this.profileDetailKind === 1) {
      return 'AI 内容说明';
    }
    if (this.profileDetailKind === 2) {
      return '隐私说明';
    }
    return '关于厨房主理人';
  }

  @Builder
  private DetailParagraph(title: string, content: string) {
    Column({ space: 8 }) {
      Text(title)
        .width('100%')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(JADE)
      Text(content)
        .width('100%')
        .fontSize(14)
        .lineHeight(23)
        .fontColor(INK)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
  }

  private loginPolicyTitle(): string {
    return this.loginPolicyDetailKind === 1 ? 'AI 服务规则' : '隐私政策';
  }

  @Builder
  private LoginPolicyPage() {
    Column() {
      Row({ space: 10 }) {
        Button('‹')
          .width(40)
          .height(40)
          .fontSize(28)
          .fontColor(JADE)
          .backgroundColor(JADE_SOFT)
          .borderRadius(14)
          .onClick(() => this.loginPolicyDetailKind = 0)
        Text(this.loginPolicyTitle())
          .layoutWeight(1)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(JADE)
      }
      .width('100%')
      .height(68)
      .padding({ left: 16, right: 16 })
      .backgroundColor(CARD)

      Scroll() {
        Column() {
          if (this.loginPolicyDetailKind === 1) {
            this.DetailParagraph('服务内容', '厨房主理人使用 AI 根据你主动发送的菜名、食材、用量和步骤，协助整理与修改家庭菜谱。它不是通用聊天、医疗、营养治疗或食品安全判断服务。')
            Divider().color(LINE)
            this.DetailParagraph('生成内容提示', '对话回复与菜谱均由 AI 生成，可能存在理解偏差或补充。保存和烹饪前，请自行核对食材、过敏原、用量、火候与步骤。')
            Divider().color(LINE)
            this.DetailParagraph('使用边界', '请勿发送违法、有害、侵权或与菜谱整理无关的内容。出现疑似食品安全风险时，请停止食用并咨询专业人员。')
          } else {
            this.DetailParagraph('收集的信息', '为完成登录与会话验证，应用会处理华为账号授权返回的必要身份标识、已授权展示的昵称或头像，以及登录时间。')
            Divider().color(LINE)
            this.DetailParagraph('菜谱数据', '只有你主动发送的菜谱文字才会提交至云函数并交给 AI 整理。未发送的输入不会上传；照片只作为本机菜谱封面，不用于识别。')
            Divider().color(LINE)
            this.DetailParagraph('存储与控制', '菜谱保存在当前设备。你可以在“我的”中退出账号，清除本机会话；已保存的本地菜谱不会随退出账号删除。')
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 10, bottom: 28 })
        .backgroundColor(CARD)
        .borderRadius(18)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
  }

  @Builder
  private ProfileDetailPage() {
    Column() {
      Row({ space: 10 }) {
        Button('‹')
          .width(40)
          .height(40)
          .fontSize(28)
          .fontColor(JADE)
          .backgroundColor(JADE_SOFT)
          .borderRadius(14)
          .onClick(() => this.profileDetailKind = 0)
        Text(this.profileDetailTitle())
          .layoutWeight(1)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(JADE)
      }
      .width('100%')
      .height(68)
      .padding({ left: 16, right: 16 })
      .backgroundColor(CARD)

      Scroll() {
        Column() {
          if (this.profileDetailKind === 1) {
            this.DetailParagraph('内容如何生成', '对话回复和整理后的菜谱由 AI 根据你输入的菜名、食材、用量和制作步骤生成。AI 可能理解偏差，也可能补充原文没有明确提供的信息。')
            Divider().color(LINE)
            this.DetailParagraph('如何核对', '保存或照着烹饪前，请核对食材、过敏原、用量、火候和步骤。“AI 估算”表示这项用量不是你明确提供的，应结合实际情况调整。')
            Divider().color(LINE)
            this.DetailParagraph('能力边界', '厨房主理人只协助整理和修改家常菜谱，不提供医疗、营养治疗、食物中毒判断或其他专业结论。遇到食品安全风险时，请停止食用并咨询专业人员。')
          } else if (this.profileDetailKind === 2) {
            this.DetailParagraph('账号信息', '登录使用华为账号的 OpenID/UnionID 建立应用会话；本机只保存短期会话、脱敏账号标识以及已授权展示的昵称或匿名账号和头像地址。')
            Divider().color(LINE)
            this.DetailParagraph('菜谱与 AI', '你发送的菜谱文字会经华为云函数交给 DeepSeek 整理。未发送的输入和本地菜谱不会用于 AI 请求。菜谱照片只保存在本机作为封面，不上传识别。')
            Divider().color(LINE)
            this.DetailParagraph('你的控制', '可在账号卡片点击“退出账号”，清除本机会话并请求撤销本应用的华为账号授权。本机已经保存的菜谱不会随退出登录删除。')
          } else {
            this.DetailParagraph('厨房主理人', '把一次做成功的经验，整理成以后还能复刻的家庭菜谱。它更像一本会帮你归纳的私人菜谱簿，而不是通用聊天助手。')
            Divider().color(LINE)
            this.DetailParagraph('数据原则', '菜谱本地优先，照片只作本机封面；只有主动发送的文字才会用于 AI 整理。')
            Divider().color(LINE)
            this.DetailParagraph('版本', '1.0.0')
          }
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 10, bottom: 28 })
        .backgroundColor(CARD)
        .borderRadius(18)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 24 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(PAPER)
  }

  @Builder
  private HuaweiAccountCard() {
    if (this.identityVerified) {
      Column({ space: 14 }) {
        Row({ space: 13 }) {
          if (this.verifiedAvatarUrl.length > 0) {
            Image(this.verifiedAvatarUrl)
              .width(52)
              .height(52)
              .objectFit(ImageFit.Cover)
              .borderRadius(26)
          } else {
            Stack() {
              Text(this.accountInitial())
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
            }
            .width(52)
            .height(52)
            .backgroundColor(JADE)
            .borderRadius(26)
          }
          Column({ space: 5 }) {
            Row({ space: 7 }) {
              Text(this.accountDisplayName())
                .layoutWeight(1)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(INK)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text('已登录')
                .fontSize(11)
                .fontColor(JADE)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(JADE_SOFT)
                .borderRadius(10)
            }
            .width('100%')
            Text(`华为账号 ${this.verifiedAccountId}`)
              .width('100%')
              .fontSize(12)
              .fontColor(MUTED)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        Divider().color(LINE)

        Row() {
          Column({ space: 4 }) {
            Text('账号身份已由华为服务端校验')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(INK)
            Text(`登录于 ${this.formatDateTime(this.verifiedLoginAt)}`)
              .fontSize(11)
              .fontColor(MUTED)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Button('退出账号')
            .height(34)
            .fontSize(12)
            .fontColor('#A44332')
            .backgroundColor('#F8E7E3')
            .borderRadius(11)
            .onClick(() => this.showHuaweiLogoutConfirm = true)
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(CARD)
      .border({ width: 1, color: LINE })
      .borderRadius(18)
    } else {
      Row({ space: 13 }) {
        Stack() {
          Text('华')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .width(52)
        .height(52)
        .backgroundColor(JADE)
        .borderRadius(26)
        Column({ space: 5 }) {
          Text('尚未登录华为账号')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(INK)
          Text('登录后可使用 AI 菜谱整理')
            .fontSize(12)
            .fontColor(MUTED)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button('去登录')
          .height(36)
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor(JADE)
          .borderRadius(11)
          .onClick(() => this.currentPage = 1)
      }
      .width('100%')
      .padding(16)
      .backgroundColor(CARD)
      .border({ width: 1, color: LINE })
      .borderRadius(18)
    }
  }

  @Builder
  private ProfilePage() {
    Column() {
      Row() {
        Column({ space: 2 }) {
        Text('我的')
          .width('100%')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(JADE)
          Text('账号、服务与应用说明')
            .width('100%')
            .fontSize(12)
            .fontColor(MUTED)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(68)
      .padding({ left: 18, right: 18 })
      .backgroundColor(CARD)

      Scroll() {
        Column({ space: 16 }) {
          this.HuaweiAccountCard()
          Column() {
            this.ProfileRow('本机菜谱', `${this.recipes.length} 道菜保存在当前设备`, '本地优先')
            Divider().color(LINE)
            this.ProfileRow('AI 服务', this.aiOnline ?
              '菜谱整理和修改服务当前可用。' :
              '服务当前不可用，本地菜谱不会丢失。',
              this.aiOnline ? '已连接' : '待连接')
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor(CARD)
          .borderRadius(18)
          Column() {
            this.ProfileLinkRow('AI 内容说明', '生成内容、核对方法与能力边界', 1)
            Divider().color(LINE).margin({ left: 16 })
            this.ProfileLinkRow('隐私说明', '账号、菜谱文字和照片如何处理', 2)
            Divider().color(LINE).margin({ left: 16 })
            this.ProfileLinkRow('关于', '产品定位、数据原则与版本', 3)
          }
          .width('100%')
          .backgroundColor(CARD)
          .borderRadius(18)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 26 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
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
    .height(54)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.currentPage === page ? '#E9F1EC' : '#00000000')
    .borderRadius(15)
    .onClick(() => {
      const wasShowingDraftDetail: boolean = this.showDraftRecipeDetail;
      this.currentPage = page;
      this.profileDetailKind = 0;
      this.loginPolicyDetailKind = 0;
      if (wasShowingDraftDetail && page === 1) {
        this.returnToConversation();
      } else {
        this.showDraftRecipeDetail = false;
      }
      if (page === 0 || page === 1) {
        this.closeDetail();
      }
    })
  }

  @Builder
  private BottomNavigation() {
    Row({ space: 12 }) {
      this.NavItem('菜谱', '▤', 0)
      this.NavItem('记录', '＋', 1)
      this.NavItem('我的', '●', 2)
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 16 })
    .justifyContent(FlexAlign.SpaceAround)
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
  private PhotoConfirm() {
    Column() {
      Blank()
      Column({ space: 12 }) {
        Row() {
          Text('使用这张照片作为封面？')
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
            .onClick(() => this.cancelPendingPhoto())
        }
        .width('100%')
        Image(this.pendingPhotoUri)
          .width('100%')
          .height(220)
          .objectFit(ImageFit.Cover)
          .borderRadius(16)
        Button(this.isWorking ? '正在保存…' : '使用这张照片')
          .width('100%')
          .height(46)
          .fontColor('#FFFFFF')
          .backgroundColor(JADE)
          .borderRadius(14)
          .enabled(!this.isWorking)
          .onClick(() => this.confirmPendingPhoto())
        Button('重新选择')
          .width('100%')
          .height(44)
          .fontColor(JADE)
          .backgroundColor(JADE_SOFT)
          .borderRadius(14)
          .enabled(!this.isWorking)
          .onClick(() => this.repickPendingPhoto())
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
              this.showHuaweiLogoutConfirm = false;
            })
          Button(kind === 0 ? '删除' : kind === 1 ? '放弃草稿' : '退出账号')
            .layoutWeight(1)
            .height(44)
            .fontColor('#FFFFFF')
            .backgroundColor(CHILI)
            .borderRadius(14)
            .onClick(() => {
              if (kind === 0) {
                this.confirmDelete();
              } else if (kind === 1) {
                this.discardDraft();
              } else {
                void this.logoutHuaweiAccount();
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
            if (this.profileDetailKind > 0) {
              this.ProfileDetailPage()
            } else {
              this.ProfilePage()
            }
          } else if (this.loginPolicyDetailKind > 0) {
            this.LoginPolicyPage()
          } else if (IDENTITY_VERIFICATION_ENABLED && !this.identityVerified) {
            this.IdentityVerificationPage()
          } else if (this.showDraftRecipeDetail) {
            this.DraftRecipeDetailPage()
          } else {
            this.ConversationPage()
          }
        }
        .width('100%')
        .layoutWeight(1)
        if (this.profileDetailKind === 0 && this.loginPolicyDetailKind === 0) {
          this.BottomNavigation()
        }
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
      if (this.showPhotoConfirm) {
        this.PhotoConfirm()
      }
      if (this.showDeleteConfirm) {
        this.ConfirmDialog('删除这道菜谱？', '删除后有 2 秒可以撤销，之后会从本机菜谱夹中移除。', 0)
      }
      if (this.showDiscardConfirm) {
        this.ConfirmDialog('放弃当前草稿？', '已经整理的内容会被清空，这个操作不能恢复。', 1)
      }
      if (this.showHuaweiLogoutConfirm) {
        this.ConfirmDialog('退出华为账号？', '将清除本机登录会话，并请求华为 Account Kit 取消本应用授权。本机菜谱不会删除。', 2)
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
