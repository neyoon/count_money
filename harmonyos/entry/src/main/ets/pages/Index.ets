import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';
import {
  Ledger, Asset, Category, Transaction, AmountCandidate, CategoryTotal, Repayment,
  ASSET_KINDS, ASSET_NAMES, emptyLedger, clone, cents, money, debt, newAsset,
  balances, overview, categoryTotals, localMonth, saveTransaction, deleteTransaction,
  parseBackup, exportBackup, amountCandidates, assetValues, repaymentRows, addFundActivity, dailyFlows, DailyFlow, FundActivity, Overview, TransactionRowSnapshot, transactionRows, calendarDay, calendarCells, keypadAmount
} from '../core/Ledger';
import { LedgerRepository } from '../services/LedgerRepository';
import { BackupFiles } from '../services/BackupFiles';
import { ScreenshotOCR } from '../services/ScreenshotOCR';
import { AppColors } from '../theme/AppColors';
import { TransactionSource } from './TransactionSource';
import { CategoryRing } from './CategoryRing';
import { CategoryStyle } from '../theme/CategoryStyle';

@Entry
@Component
struct Index {
  @State @Watch('refreshData') private ledger: Ledger = emptyLedger();
  @State private ready: boolean = false;
  @State private busy: boolean = false;
  @State private startupError: string = '';
  @State private page: number = 2;
  @State @Watch('refreshTransactions') private expandedDetails: boolean = false;
  @State @Watch('refreshTransactions') private selectedDay: number = new Date().getDate();
  @State private monthCells: number[] = calendarCells(localMonth(new Date().toISOString()));
  @State private daysWithEntries: number[] = [];
  @State private windowWidth: number = 400;
  @State private hidden: boolean = false;
  @State @Watch('detailMonthChanged') private month: string = localMonth(new Date().toISOString());
  @State @Watch('refreshTransactions') private search: string = '';
  @State private editorOpen: boolean = false;
  @State private editingID: string = '';
  @State private kind: string = 'expense';
  @State private amount: string = '';
  @State private title: string = '';
  @State private accountID: string = '';
  @State private paymentID: string = '';
  @State private categoryKey: string = 'expense_food';
  @State private occurredAt: string = new Date().toISOString();
  @State private installments: string = '';
  @State private recognizedText: string = '';
  @State private candidates: AmountCandidate[] = [];
  @State private assetID: string = '';
  @State private assetName: string = '';
  @State private assetKindIndex: number = 0;
  @State private assetBalance: string = '0.00';
  @State private assetEditing: boolean = false;
  @State private expandedDebt: string = '';
  @State private profitLoss: boolean = false;
  @State private initializationMode: boolean = false;
  @State private fundCostInput: string = '';
  @State private categoryName: string = '';
  @State private categoryKind: string = 'expense';
  @StorageLink('launchEpoch') @Watch('onLaunch') private launchEpoch: number = 0;
  @State private cachedValues: number[] = [];
  @State private cachedNet: number = 0;
  @State private cachedHoldings: number = 0;
  @State private cachedFunds: number = 0;
  @State private cachedDebt: number = 0;
  @State private cachedRepayment: number = 0;
  @State private cachedOverview: Overview = { income: 0, expense: 0, net: 0 };
  @State private cachedIncome: CategoryTotal[] = [];
  @State private cachedExpense: CategoryTotal[] = [];
  @State private cachedFlows: DailyFlow[] = [];
  @State private cachedScale: number = 1;
  @State private recentRows: TransactionRowSnapshot[] = [];
  @State private detailTransactions: Transaction[] = [];
  private sortedTransactions: Transaction[] = [];
  private readonly recentDays: number = 7;
  @State private recentDayCount: number = 0;
  private recentDaySource: TransactionSource = new TransactionSource();
  private recentDayScroller: Scroller = new Scroller();
  private transactionSource: TransactionSource = new TransactionSource();
  private detailScroller: Scroller = new Scroller();
  private dashboardMonth: string = '';

  private refreshData(): void {
    this.cachedValues = assetValues(this.ledger);
    let holdings = 0; let funds = 0; let liabilities = 0; let repayment = 0;
    this.ledger.assets.forEach((asset: Asset, index: number) => {
      if (debt(asset.kind)) {
        liabilities += this.totalDebt(asset, this.cachedValues[index]);
        repayment += cents(asset.repayments.find((r: Repayment) => r.monthOffset === 0)?.amount || '0');
      } else if (asset.kind === 'fund') funds += this.cachedValues[index];
      else holdings += this.cachedValues[index];
    });
    this.cachedHoldings = holdings; this.cachedFunds = funds; this.cachedDebt = liabilities;
    this.cachedRepayment = repayment; this.cachedNet = holdings + funds - liabilities;
    this.sortedTransactions = this.ledger.transactions.slice().sort((a: Transaction, b: Transaction) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt));
    this.refreshDashboard(); this.refreshTransactions();
  }
  private refreshDashboard(): void {
    this.dashboardMonth = localMonth(new Date().toISOString());
    this.cachedOverview = overview(this.ledger, this.dashboardMonth);
    this.cachedIncome = categoryTotals(this.ledger, this.dashboardMonth, 'income');
    this.cachedExpense = categoryTotals(this.ledger, this.dashboardMonth, 'expense');
    this.cachedFlows = dailyFlows(this.ledger, this.dashboardMonth);
    this.cachedScale = Math.max(1, ...this.cachedFlows.map((day: DailyFlow) => Math.max(day.income, day.expense)));
    this.recentRows = transactionRows(this.sortedTransactions.filter((t: Transaction) => localMonth(t.occurredAt) === this.dashboardMonth).slice(0, 10));
    this.refreshRecentDays();
  }
  private refreshRecentDays(): void {
    const start = new Date(); start.setHours(0, 0, 0, 0); start.setDate(start.getDate() - this.recentDays + 1);
    const end = new Date(); end.setHours(23, 59, 59, 999);
    const rows = transactionRows(this.sortedTransactions.filter((t: Transaction) => {
      const date = Date.parse(t.occurredAt); return date >= start.getTime() && date <= end.getTime();
    }));
    this.recentDayCount = rows.length;
    this.recentDaySource.replace(rows);
  }
  private detailMonthChanged(): void {
    this.monthCells = calendarCells(this.month);
    this.selectedDay = calendarDay(this.month, new Date().getDate());
    this.refreshTransactions();
  }
  private refreshTransactions(): void {
    const needle = this.search.toLowerCase();
    const monthly = this.sortedTransactions.filter((t: Transaction) => localMonth(t.occurredAt) === this.month);
    this.daysWithEntries = Array.from(new Set(monthly.map((t: Transaction) => new Date(t.occurredAt).getDate())));
    this.detailTransactions = monthly.filter((t: Transaction) =>
      (!this.expandedDetails || new Date(t.occurredAt).getDate() === this.selectedDay) &&
      (!needle || `${t.title} ${t.accountName} ${t.paymentAccountName || ''} ${this.categoryLabel(t.categoryPresetKey)} ${t.amount}`.toLowerCase().includes(needle)));
    this.transactionSource.replace(transactionRows(this.detailTransactions));
  }
  private selectCalendarDay(day: number): void {
    this.selectedDay = day;
    this.detailScroller.scrollEdge(Edge.Top);
  }
  private isToday(day: number): boolean {
    const today = new Date();
    return this.month === localMonth(today.toISOString()) && day === today.getDate();
  }
  private selectPage(page: number): void {
    if (page === this.page) return;
    if (page === 0 && this.dashboardMonth !== localMonth(new Date().toISOString())) this.refreshDashboard();
    this.page = page;
  }
  private pageScroller: Scroller = new Scroller();
  private repository: LedgerRepository = new LedgerRepository();

  aboutToAppear(): void { this.initialize(); }

  private notify(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500 });
  }

  private async initialize(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.ledger = await this.repository.open(context);
      if (!this.ledger.categories.some((c: Category) => c.presetKey === 'expense_transfer')) {
        const transfer = emptyLedger().categories.find((c: Category) => c.presetKey === 'expense_transfer');
        if (transfer) {
          const next = clone(this.ledger); next.categories.push(transfer);
          await this.repository.save(next); this.ledger = next;
        }
      }
      this.accountID = this.ledger.assets.find((a: Asset) => a.kind !== 'fund')?.id || '';
      this.refreshData();
      this.ready = true;
      this.onLaunch();
    } catch (error) { this.startupError = `无法打开账本：${(error as Error).message}`; }
  }

  private onLaunch(): void {
    if (!this.ready || this.busy) return;
    const action = AppStorage.get<string>('launchAction') || '';
    AppStorage.setOrCreate('launchAction', '');
    if (action === 'entry') this.startEntry();
    if (action === 'ocr') { this.startEntry(); this.pickScreenshot(); }
  }

  private display(value: number): string { return this.hidden ? '••••' : `¥ ${money(value)}`; }
  private categoryLabel(key: string): string { return this.ledger.categories.find((c: Category) => c.presetKey === key)?.name || '基金盈亏'; }
  private eligibleAccounts(payment: boolean = false): Asset[] {
    return this.ledger.assets.filter((a: Asset) => {
      if (this.kind === 'fundProfit') return a.kind === 'fund';
      if (this.kind === 'transfer') return !debt(a.kind) && a.kind !== 'fund';
      if (this.categoryKey === 'expense_repayment') return payment ? !debt(a.kind) && a.kind !== 'fund' : debt(a.kind);
      if (this.categoryKey === 'expense_fund_purchase') return payment ? !debt(a.kind) && a.kind !== 'fund' : a.kind === 'fund';
      if (this.categoryKey === 'income_fund_redemption') return payment ? a.kind === 'fund' : !debt(a.kind) && a.kind !== 'fund';
      return a.kind !== 'fund';
    });
  }
  private accountIcon(id: string): Resource {
    const kind = this.ledger.assets.find((asset: Asset) => asset.id === id)?.kind || '';
    if (kind === 'cash') return $r('app.media.account_cash');
    if (kind === 'debitCard') return $r('app.media.account_debit');
    if (kind === 'creditCard') return $r('app.media.account_credit');
    if (kind === 'fund') return $r('app.media.account_fund');
    if (kind === 'alipay' || kind === 'alipayYuEBao') return $r('app.media.account_alipay');
    if (kind === 'wechatPay' || kind === 'wechatChangePass') return $r('app.media.account_wechat');
    if (debt(kind)) return $r('app.media.account_debt');
    return $r('app.media.account_wallet');
  }
  private accountOptions(payment: boolean = false): SelectOption[] {
    return this.eligibleAccounts(payment).map((a: Asset): SelectOption => { return { value: a.name, icon: this.accountIcon(a.id) }; });
  }
  private optionIndex(id: string, payment: boolean = false): number {
    return this.eligibleAccounts(payment).findIndex((a: Asset) => a.id === id);
  }
  private normalizeAccounts(): void {
    if (!this.eligibleAccounts().some((a: Asset) => a.id === this.accountID)) this.accountID = this.eligibleAccounts()[0]?.id || '';
    if (!this.eligibleAccounts(true).some((a: Asset) => a.id === this.paymentID)) this.paymentID = this.eligibleAccounts(true).find((a: Asset) => a.id !== this.accountID)?.id || '';
  }
  private assetOptions(): SelectOption[] { return ASSET_NAMES.map((name: string): SelectOption => { return { value: name }; }); }
  private selectedAccount(id: string): number { return this.ledger.assets.findIndex((a: Asset) => a.id === id); }
  private accountName(id: string): string { return this.ledger.assets.find((a: Asset) => a.id === id)?.name || '请选择账户'; }
  private categories(): Category[] {
    return this.ledger.categories.filter((c: Category) => this.kind === 'transfer' ? c.presetKey === 'expense_transfer' : c.kind === this.kind && c.presetKey !== 'expense_transfer')
      .sort((a: Category, b: Category) => a.sortOrder - b.sortOrder);
  }
  private special(): boolean { return ['expense_transfer', 'expense_repayment', 'expense_fund_purchase', 'income_fund_redemption'].includes(this.categoryKey); }
  private transactionDetail(t: Transaction): string {
    const accounts = t.kind === 'transfer' ? `${t.paymentAccountName || this.accountName(t.paymentAccountID || '')} → ${t.accountName}` : `${this.categoryLabel(t.categoryPresetKey)} · ${t.accountName}`;
    return `${accounts} · ${new Date(t.occurredAt).toLocaleDateString()}`;
  }
  private amountColor(value: number): Resource { return value > 0 ? AppColors.success : value < 0 ? AppColors.danger : AppColors.muted; }
  private assetValue(index: number): number { return this.cachedValues[index] || 0; }
  private netAssets(): number { return this.cachedNet; }
  private totalDebt(asset: Asset, balance: number): number {
    const schedule = asset.repayments.reduce((sum: number, r: Repayment) => sum + cents(r.amount), 0);
    return Math.max(balance, schedule);
  }

  private startEntry(keepSelection: boolean = false): void {
    this.page = 2; this.editorOpen = true; this.editingID = '';
    if (!keepSelection) { this.kind = 'expense'; this.categoryKey = 'expense_food'; }
    this.profitLoss = false; this.amount = ''; this.title = '';
    this.installments = ''; this.occurredAt = new Date().toISOString();
    this.normalizeAccounts();
    this.recognizedText = ''; this.candidates = [];
  }

  private entryDateLabel(): string {
    const date = new Date(this.occurredAt);
    return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`;
  }
  private entryTimeLabel(): string {
    const date = new Date(this.occurredAt);
    return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`;
  }

  private selectDate(): void {
    this.getUIContext().showDatePickerDialog({ selected: new Date(this.occurredAt),
      start: new Date(1970, 0, 1), end: new Date(2100, 11, 31),
      onDateAccept: (selected: Date) => {
        const date = new Date(this.occurredAt);
        date.setFullYear(selected.getFullYear(), selected.getMonth(), selected.getDate());
        this.occurredAt = date.toISOString(); this.editorOpen = true;
      }
    });
  }

  private selectTime(): void {
    this.getUIContext().showTimePickerDialog({ selected: new Date(this.occurredAt), useMilitaryTime: true,
      onAccept: (selected: TimePickerResult) => {
        const date = new Date(this.occurredAt);
        date.setHours(selected.hour || 0, selected.minute || 0, 0, 0);
        this.occurredAt = date.toISOString(); this.editorOpen = true;
      }
    });
  }

  private selectMonth(): void {
    const parts = this.month.split('-');
    const currentYear = Number(parts[0]);
    const firstYear = Math.min(1998, currentYear);
    const lastYear = Math.max(2100, currentYear);
    const years: string[] = [];
    const months: string[] = [];
    for (let year = firstYear; year <= lastYear; year++) years.push(`${year}年`);
    for (let month = 1; month <= 12; month++) months.push(`${month}月`);
    this.getUIContext().showTextPickerDialog({
      range: [years, months], selected: [currentYear - firstYear, Number(parts[1]) - 1], canLoop: false,
      onAccept: (result: TextPickerResult) => {
        const indexes = result.index as number[];
        if (indexes.length === 2) this.month = `${firstYear + indexes[0]}-${String(indexes[1] + 1).padStart(2, '0')}`;
      }
    });
  }

  private monthLabel(): string {
    const parts = this.month.split('-');
    return `${parts[0]}年${Number(parts[1])}月`;
  }

  private edit(t: Transaction): void {
    if (t.kind === 'fundProfit') { this.notify('请在资产页查看基金盈亏'); return; }
    this.editingID = t.id; this.kind = t.kind; this.categoryKey = t.categoryPresetKey;
    this.amount = t.amount; this.title = t.title; this.accountID = t.accountID || '';
    this.paymentID = t.paymentAccountID || ''; this.installments = t.installmentMonths?.toString() || '';
    this.occurredAt = t.occurredAt; this.editorOpen = true; this.page = 2;
    this.candidates = []; this.recognizedText = '';
  }

  private async commit(next: Ledger): Promise<void> {
    await this.repository.save(next);
    this.ledger = next;
  }

  private async save(): Promise<void> {
    if (this.busy || !this.ready) return;
    this.busy = true;
    try {
      if (this.installments && !/^\d+$/.test(this.installments)) throw new Error('分期期数必须是整数');
      if (this.kind === 'fundProfit') {
        await this.commit(addFundActivity(this.ledger, this.accountID, { id: util.generateRandomUUID(), kind: 'valuation', amount: money((this.profitLoss ? -1 : 1) * Math.abs(cents(this.amount))), occurredAt: this.occurredAt, note: this.title }));
        this.startEntry(true); this.editorOpen = false; return;
      }
      const transaction: Transaction = {
        id: this.editingID || util.generateRandomUUID(), kind: this.kind, title: this.title.trim(),
        categoryPresetKey: this.categoryKey, accountID: this.accountID,
        accountName: this.accountName(this.accountID), amount: this.amount,
        occurredAt: new Date(this.occurredAt).toISOString()
      };
      if (this.special()) transaction.paymentAccountID = this.paymentID;
      if (this.installments) transaction.installmentMonths = Number(this.installments);
      await this.commit(saveTransaction(this.ledger, transaction));
      this.startEntry(true); this.editorOpen = false;

    } catch (error) { this.notify((error as Error).message); }
    finally { this.busy = false; }
  }

  private remove(t: Transaction): void {
    this.getUIContext().showAlertDialog({
      title: '删除这笔账？', message: `${t.title || this.categoryLabel(t.categoryPresetKey)} · ${this.display(cents(t.amount))}\n关联的还款计划和基金变动也会撤回。`,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', action: () => { this.performDelete(t); } }
    });
  }
  private async performDelete(t: Transaction): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try { await this.commit(deleteTransaction(this.ledger, t.id)); this.editorOpen = false;  }
    catch (error) { this.notify((error as Error).message); }
    finally { this.busy = false; }
  }

  private applyText(text: string): void {
    this.recognizedText = text.slice(0, 1000); this.candidates = amountCandidates(text);
    this.editorOpen = true; this.page = 2;
    if (this.candidates.length === 0) { this.notify('没有找到可靠金额，请手动输入'); return; }
    this.amount = this.candidates[0].amount; this.kind = this.candidates[0].kind;
    this.categoryKey = this.kind === 'income' ? 'income_refund' : 'expense_food';

  }

  private async pickScreenshot(): Promise<void> {
    if (this.busy || !this.ready) return;
    if (this.amount || this.editingID) {
      this.getUIContext().showAlertDialog({ title: '重新识别截图？', message: '当前未保存的输入将替换为新的识别草稿。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '选择截图', action: () => { this.startEntry(); this.runOCR(); } } });
      return;
    }
    this.startEntry(); await this.runOCR();
  }
  private async runOCR(): Promise<void> {
    this.busy = true;
    try { const text = await ScreenshotOCR.pick(); if (text) this.applyText(text); }
    catch (error) { this.notify(`识别未完成：${(error as Error).message}`); }
    finally { this.busy = false; }
  }

  private async dropped(event: DragEvent): Promise<void> {
    if (this.busy || !this.ready) return;
    if (this.amount || this.editingID) { this.notify('请先保存或取消当前草稿，再拖入内容'); return; }
    this.busy = true;
    try {
      const records = event.getData().getRecords();
      for (let i = 0; i < records.length; i++) {
        const record = records[i];
        if (record.getType() === uniformTypeDescriptor.UniformDataType.PLAIN_TEXT) {
          const plain = record as unifiedDataChannel.PlainText;
          this.startEntry(); this.applyText(plain.textContent); return;
        }
        if (record.getType() === uniformTypeDescriptor.UniformDataType.IMAGE) {
          const img = record as unifiedDataChannel.Image;
          this.startEntry();
          this.applyText(await ScreenshotOCR.recognize(img.imageUri)); return;
        }
      }
      this.notify('请拖入文字或图片；也可以点击“识别截图”');
    } catch (error) { this.notify(`拖入未完成：${(error as Error).message}`); }
    finally { this.busy = false; }
  }

  private editAsset(asset: Asset): void {
    if (!this.initializationMode) return;
    this.assetID = asset.id; this.assetName = asset.name; this.assetBalance = asset.balance;
    this.fundCostInput = asset.fundCost ?? '0.00';
    if (asset.kind === 'fund') this.assetBalance = asset.fundMarketValue ?? asset.balance;
    this.assetKindIndex = ASSET_KINDS.indexOf(asset.kind); this.assetEditing = true;
  }
  private async saveAsset(): Promise<void> {
    if (!this.initializationMode) return;
    if (this.busy) return;
    this.busy = true;
    try {
      const next = clone(this.ledger);
      const existing = next.assets.find((a: Asset) => a.id === this.assetID);
      if (existing) {
        if (!this.assetName.trim()) throw new Error('请填写账户名称');
        existing.name = this.assetName.trim(); existing.balance = money(cents(this.assetBalance));
        if (existing.kind === 'fund') { existing.fundMarketValue = existing.balance; existing.fundCost = money(cents(this.fundCostInput)); }
        next.transactions.forEach((t: Transaction) => {
          if (t.accountID === existing.id) t.accountName = existing.name;
          if (t.paymentAccountID === existing.id) t.paymentAccountName = existing.name;
        });
      } else next.assets.push(newAsset(util.generateRandomUUID(), this.assetName, ASSET_KINDS[this.assetKindIndex], this.assetBalance));
      await this.commit(next); this.assetEditing = false;
    } catch (error) { this.notify((error as Error).message); }
    finally { this.busy = false; }
  }
  private async addCategory(): Promise<void> {
    if (this.busy || !this.categoryName.trim()) return;
    this.busy = true;
    try {
      const next = clone(this.ledger); const id = util.generateRandomUUID();
      next.categories.push({ id: id, presetKey: `${this.categoryKind}_${id}`, name: this.categoryName.trim(),
        kind: this.categoryKind, symbolName: 'tag.fill', sortOrder: next.categories.length * 10, isSystemPreset: false });
      await this.commit(next); this.categoryName = '';
    } catch (error) { this.notify((error as Error).message); }
    finally { this.busy = false; }
  }

  private async exportFile(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try { if (await BackupFiles.write(exportBackup(this.ledger))) this.notify('备份已导出'); }
    catch (error) { this.notify((error as Error).message); }
    finally { this.busy = false; }
  }
  private async importFile(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      const raw = await BackupFiles.read(); if (!raw) return;
      const imported = parseBackup(raw);
      this.getUIContext().showAlertDialog({
        title: '导入并替换当前账本？',
        message: `备份包含 ${imported.assets.length} 个账户、${imported.categories.length} 个分类、${imported.transactions.length} 笔账。\n请先导出当前账本。导入前还会自动保留本机恢复副本。`,
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '确认替换', action: () => { this.replace(imported); } }
      });
    } catch (error) {
      this.getUIContext().showAlertDialog({ title: '导入失败', message: (error as Error).message,
        primaryButton: { value: '知道了', action: () => {} } });
    }
    finally { this.busy = false; }
  }
  private async replace(imported: Ledger): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      await this.commit(imported); this.editorOpen = false;
      this.accountID = imported.assets.find((a: Asset) => a.kind !== 'fund')?.id || '';
      this.paymentID = ''; this.assetEditing = false;
      if (imported.transactions.length > 0) this.month = localMonth(imported.transactions[0].occurredAt);
      this.notify('账本已更新');
    }
    catch (error) { this.notify((error as Error).message); }
    finally { this.busy = false; }
  }
  private navigationIcon(index: number): Resource {
    if (this.page === [1, 0, 2, 3, 4][index]) {
      if (index === 0) return $r('app.media.nav_details_active');
      if (index === 1) return $r('app.media.nav_overview_active');
      if (index === 2) return $r('app.media.nav_entry_active');
      if (index === 3) return $r('app.media.nav_assets_active');
      return $r('app.media.nav_settings_active');
    }
    if (index === 0) return $r('app.media.nav_details');
    if (index === 1) return $r('app.media.nav_overview');
    if (index === 2) return $r('app.media.nav_entry');
    if (index === 3) return $r('app.media.nav_assets');
    return $r('app.media.nav_settings');
  }
  @Builder private nav() {
    Row({ space: 0 }) {
      ForEach(['明细', '总览', '记账', '资产', '设置'], (label: string, index: number) => {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 3 }) {
            Image(this.navigationIcon(index)).width(index === 2 ? 28 : 22).height(index === 2 ? 28 : 22)
              .objectFit(ImageFit.Contain)
            Text(label).fontSize(11).fontColor(this.page === [1, 0, 2, 3, 4][index] ? AppColors.accent : AppColors.muted)
              .fontWeight(this.page === [1, 0, 2, 3, 4][index] ? FontWeight.Bold : FontWeight.Regular)
          }.justifyContent(FlexAlign.Center).height(50)
        }.layoutWeight(1).height(54).borderRadius(12)
          .backgroundColor(this.page === [1, 0, 2, 3, 4][index] ? AppColors.accentTint : Color.Transparent)
          .accessibilityText(label).onClick(() => { this.selectPage([1, 0, 2, 3, 4][index]); })
      })
    }.width('100%').padding({ top: 4, bottom: 4 }).backgroundColor(AppColors.surface)
      .border({ width: { top: 1 }, color: AppColors.line })
  }

  @Builder private overviewCard() {
    Column({ space: 18 }) {
      Row() {
        Text('本月支出').fontSize(13).fontColor(AppColors.muted).layoutWeight(1)
        Button(this.hidden ? '显示' : '隐藏').fontSize(11).fontColor(AppColors.muted).backgroundColor(AppColors.secondarySurface)
          .onClick(() => { this.hidden = !this.hidden; })
      }.width('100%')
      Text(this.display(this.cachedOverview.expense)).fontSize(36).fontWeight(FontWeight.Bold)
        .fontColor(AppColors.danger).maxLines(1).minFontSize(20).maxFontSize(36).width('100%')
      Row() {
        Column({ space: 6 }) {
          Text('收入').fontSize(12).fontColor(AppColors.muted)
          Text(this.display(this.cachedOverview.income)).fontSize(17).fontColor(AppColors.success)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Column({ space: 6 }) {
          Text('结余').fontSize(12).fontColor(AppColors.muted)
          Text(this.display(this.cachedOverview.net)).fontSize(17).fontColor(AppColors.ink)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      }.width('100%')
    }.padding(14).borderRadius(12).backgroundColor(AppColors.surface)
      .border({ width: 1, color: AppColors.line }).alignItems(HorizontalAlign.Start).width('100%')
  }

  @Builder private dropZone() {
    Row() {
      Text('拖入截图或文字').fontSize(12).fontColor(AppColors.muted)
    }.width('100%').justifyContent(FlexAlign.Center).padding(16).borderRadius(8)
      .border({ width: 1, color: AppColors.line, style: BorderStyle.Dashed })
      .allowDrop([uniformTypeDescriptor.UniformDataType.PLAIN_TEXT, uniformTypeDescriptor.UniformDataType.IMAGE])
      .onDrop((event: DragEvent) => { this.dropped(event); })
  }

  @Builder private transactionRow(t: Transaction) {
        Row({ space: 12 }) {
          Image(CategoryStyle.icon(t.categoryPresetKey)).width(22).height(22).objectFit(ImageFit.Contain)
            .padding(6).width(32).height(32).backgroundColor(AppColors.secondarySurface).borderRadius(10)
          Column({ space: 2 }) {
            Text(t.title || this.categoryLabel(t.categoryPresetKey)).fontSize(15).fontColor(AppColors.ink).maxLines(1)
            Text(this.transactionDetail(t))
              .fontSize(11).fontColor(AppColors.muted).maxLines(1)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text(`${t.kind === 'transfer' ? '' : t.kind === 'expense' ? '− ' : '+ '}${this.display(cents(t.amount))}`)
            .fontSize(16).fontWeight(FontWeight.Medium).fontColor(t.kind === 'transfer' ? AppColors.accent : t.kind === 'expense' ? AppColors.danger : AppColors.success)
        }.width('100%').padding({ left: 14, right: 14, top: 6, bottom: 6 }).borderRadius(8).backgroundColor(AppColors.surface)
          .onClick(() => { this.edit(t); })
  }
  private calendarWeeks(): number[] {
    const weeks: number[] = [];
    for (let index = 0; index < this.monthCells.length / 7; index++) weeks.push(index);
    return weeks;
  }
  @Builder private calendarPanel() {
    Column({ space: 8 }) {
      this.monthSelector()
      Row() {
        ForEach(['一', '二', '三', '四', '五', '六', '日'], (day: string) => {
          Text(day).fontSize(12).fontColor(AppColors.muted).layoutWeight(1).textAlign(TextAlign.Center)
        })
      }.width('100%').height(16)
      Column({ space: 2 }) {
        ForEach(this.calendarWeeks(), (week: number) => {
          Row() {
            ForEach(this.monthCells.slice(week * 7, week * 7 + 7), (day: number, index: number) => {
              Column() {
                if (day > 0) {
                  Button({ type: ButtonType.Normal }) {
                    Column({ space: 2 }) {
                      Text(String(day)).fontSize(14).fontWeight(day === this.selectedDay ? FontWeight.Bold : FontWeight.Regular)
                        .fontColor(day === this.selectedDay || this.isToday(day) ? AppColors.accent : AppColors.ink)
                        .width(28).height(28).textAlign(TextAlign.Center).borderRadius(14)
                        .backgroundColor(day === this.selectedDay ? AppColors.accentTint : Color.Transparent)
                      Circle().width(4).height(4).fill(AppColors.accent).opacity(this.daysWithEntries.includes(day) ? 1 : 0)
                    }.width(36).height(40).justifyContent(FlexAlign.Center)
                  }.width('100%').height('100%').padding(0).borderRadius(8).backgroundColor(Color.Transparent)
                    .accessibilityText(`${this.monthLabel()}${day}日${day === this.selectedDay ? '，已选中' : ''}`)
                    .onClick(() => { this.selectCalendarDay(day); })
                }
              }.layoutWeight(1).height('100%').justifyContent(FlexAlign.Center)
            }, (day: number, index: number) => `${this.month}-${week}-${index}-${day}`)
          }.width('100%').layoutWeight(1)
        }, (week: number) => `${this.month}-${week}`)
      }.width('100%').layoutWeight(1)
    }.padding(10).width('100%').height('100%').backgroundColor(AppColors.surface).borderRadius(12)
  }
  @Builder private detailsPage() {
    if (this.expandedDetails) {
      Row({ space: 16 }) {
        Column() { this.calendarPanel() }.width(0).layoutWeight(1).height('100%').justifyContent(FlexAlign.Start)
        Column() { this.detailsPane() }.width(0).layoutWeight(1).height('100%')
      }.width('100%').layoutWeight(1).padding({ top: 8 }).alignItems(VerticalAlign.Top)
    } else {
      this.detailsPane()
    }
  }
  @Builder private detailsPane() {
    Column({ space: 8 }) {
      if (this.expandedDetails) {
        Text(`${this.monthLabel()}${this.selectedDay}日 · ${this.detailTransactions.length}笔`).fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppColors.ink).width('100%')
      }
      TextInput({ text: this.search, placeholder: '搜索备注、分类、账户或金额' }).onChange((value: string) => { this.search = value; })
      if (this.detailTransactions.length === 0) {
        Text(this.expandedDetails ? '当天暂无匹配账目' : '暂无账目').fontSize(15).fontColor(AppColors.muted).padding(24)
      }
      List({ space: 4, scroller: this.detailScroller }) {
        LazyForEach(this.transactionSource, (row: TransactionRowSnapshot) => {
          ListItem() {
            Column({ space: 4 }) {
              if (row.dateHeading) {
                Text(row.dateHeading).fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppColors.muted)
                  .width('100%').padding({ top: 10, bottom: 4 })
              }
              this.transactionRow(row.transaction)
            }.width('100%')
          }
        }, (row: TransactionRowSnapshot) => row.renderKey)
      }.layoutWeight(1).width('100%').cachedCount(6).scrollBar(BarState.Off)
    }.layoutWeight(1).width('100%').enabled(!this.busy)
  }

  @Builder private transactionList() {
    Column({ space: 4 }) {
      if (this.page === 1) {
        TextInput({ text: this.search, placeholder: '搜索备注、分类、账户或金额' }).onChange((value: string) => { this.search = value; })
      }
      if (this.recentRows.length === 0) {
        Text('暂无账目').textAlign(TextAlign.Center).fontSize(15).fontColor(AppColors.muted).padding(32)
      }
      ForEach(this.recentRows, (row: TransactionRowSnapshot) => {
        if (row.dateHeading) {
          Text(row.dateHeading).fontSize(13).fontWeight(FontWeight.Medium).fontColor(AppColors.muted)
            .width('100%').padding({ top: 10, bottom: 4 })
        }
        this.transactionRow(row.transaction)
      }, (row: TransactionRowSnapshot) => row.renderKey)
    }.width('100%')
  }

  @Builder private entryHeader() {
      Row() {
        Text(this.editingID ? '编辑账目' : '记账').fontSize(21).fontWeight(FontWeight.Bold).fontColor(AppColors.primary).layoutWeight(1)
        Button('识别截图').height(28).fontSize(12).fontColor(AppColors.accent).backgroundColor(AppColors.accentTint)
          .onClick(() => { this.pickScreenshot(); })
        Button('取消').margin({ left: 6 }).height(30).fontSize(12).fontColor(AppColors.muted).backgroundColor(AppColors.secondarySurface)
          .onClick(() => { this.startEntry(); this.editorOpen = false; })
      }.width('100%')
  }
  @Builder private entryTypes() {
      Row({ space: 8 }) {
        ForEach(['expense', 'income', 'transfer', 'fundProfit'], (value: string) => {
          Button(value === 'expense' ? '支出' : value === 'income' ? '收入' : value === 'transfer' ? '转账' : '基金盈亏').height(32).layoutWeight(1).fontSize(14)
            .fontColor(this.kind === value ? AppColors.onPrimary : AppColors.muted).backgroundColor(this.kind === value ? AppColors.primary : AppColors.secondarySurface)
            .onClick(() => {
              this.kind = value; this.categoryKey = value === 'expense' ? 'expense_food' : value === 'income' ? 'income_salary' : value === 'transfer' ? 'expense_transfer' : 'fund_profit';
              this.installments = ''; this.editorOpen = true;
              this.normalizeAccounts();
            })
        })
      }
  }
  @Builder private entryFields() {
    Column({ space: this.expandedDetails ? 12 : 6 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            Text('记账日期').fontSize(12).fontColor(AppColors.muted)
            Text(this.entryDateLabel()).fontSize(13).fontColor(AppColors.accent).layoutWeight(1)
            Image($r('app.media.chevron_down')).width(12).height(12)
          }.width('100%')
        }.layoutWeight(1).height(this.expandedDetails ? 40 : 32).padding({ left: 10, right: 10 }).borderRadius(8)
          .backgroundColor(AppColors.secondarySurface).accessibilityText(`选择记账日期，${this.entryDateLabel()}`)
          .onClick(() => { this.selectDate(); })
        Button(this.entryTimeLabel()).height(this.expandedDetails ? 40 : 32).fontSize(13).fontColor(AppColors.accent)
          .backgroundColor(AppColors.secondarySurface).accessibilityText('选择记账时间')
          .onClick(() => { this.selectTime(); })
      }.width('100%')
      if (this.candidates.length > 0) {
        Text('识别金额').fontSize(11).fontColor(AppColors.muted)
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.candidates, (candidate: AmountCandidate) => {
            Button(`¥${candidate.amount}`).fontSize(12).margin({ right: 6, bottom: 6 })
              .fontColor(AppColors.primary).backgroundColor(AppColors.primaryTint).onClick(() => { this.amount = candidate.amount; this.editorOpen = true; })
          }, (candidate: AmountCandidate) => candidate.amount)
        }
      }
      if (this.kind === 'fundProfit') {
        Row({ space: 8 }) {
          Button('盈利').height(28).fontSize(12).backgroundColor(this.profitLoss ? AppColors.secondarySurface : AppColors.success).onClick(() => { this.profitLoss = false; })
          Button('亏损').height(28).fontSize(12).backgroundColor(this.profitLoss ? AppColors.danger : AppColors.secondarySurface).onClick(() => { this.profitLoss = true; })
        }
      }
      if (this.kind !== 'transfer' && this.kind !== 'fundProfit') {
        Grid() {
        ForEach(this.categories(), (category: Category) => {
          GridItem() {
            Column({ space: this.expandedDetails ? 6 : 2 }) {
              Image(CategoryStyle.icon(category.presetKey)).width(this.expandedDetails ? 22 : 18).height(this.expandedDetails ? 22 : 18).objectFit(ImageFit.Contain)
              Text(category.name).fontSize(11).fontColor(AppColors.ink).maxLines(1)
            }.width('100%').height(this.expandedDetails ? 56 : 40).justifyContent(FlexAlign.Center).borderRadius(8)
              .backgroundColor(this.categoryKey === category.presetKey ? AppColors.primaryTint : AppColors.surface)
              .border({ width: this.categoryKey === category.presetKey ? 1.5 : 1,
                color: this.categoryKey === category.presetKey ? AppColors.ink : AppColors.line })
          }
            .onClick(() => { this.categoryKey = category.presetKey; this.installments = ''; this.normalizeAccounts(); this.editorOpen = true; })
        }, (category: Category) => category.id)
      }.columnsTemplate('1fr 1fr 1fr 1fr').rowsGap(4).columnsGap(4)
        .height(Math.min(this.expandedDetails ? 176 : 128, Math.ceil(this.categories().length / 4) * (this.expandedDetails ? 56 : 40) + Math.max(0, Math.ceil(this.categories().length / 4) - 1) * 4))
        .width('100%').scrollBar(BarState.Off)
      }
      if (this.ledger.assets.length === 0) {
        Text('请先添加账户').fontSize(13).fontColor(AppColors.danger)
        Button('初始化账户').onClick(() => { this.initializationMode = true; this.page = 3; this.assetEditing = true; this.assetID = ''; this.assetName = ''; this.assetBalance = '0.00'; })
      } else if (this.kind === 'transfer') {
        Row({ space: 8 }) {
          Text('转出账户').fontSize(12).fontColor(AppColors.muted).width(64)

          Select(this.accountOptions(true)).selected(this.optionIndex(this.paymentID, true)).value(this.accountName(this.paymentID))
            .layoutWeight(1).height(this.expandedDetails ? 40 : 32).font({ size: 13 })
            .onSelect((index: number) => { this.paymentID = this.eligibleAccounts(true)[index].id; this.editorOpen = true; })
        }.width('100%')
        Row({ space: 8 }) {
          Text('转入账户').fontSize(12).fontColor(AppColors.muted).width(64)

          Select(this.accountOptions()).selected(this.optionIndex(this.accountID)).value(this.accountName(this.accountID))
            .layoutWeight(1).height(this.expandedDetails ? 40 : 32).font({ size: 13 })
            .onSelect((index: number) => { this.accountID = this.eligibleAccounts()[index].id; this.editorOpen = true; })
        }.width('100%')
      } else {
        Row({ space: 8 }) {
          Text(this.categoryKey === 'expense_repayment' ? '负债账户' : this.categoryKey === 'expense_fund_purchase' || this.kind === 'fundProfit' ? '基金账户' : '记账账户')
            .fontSize(12).fontColor(AppColors.muted).width(64)

          Select(this.accountOptions()).selected(this.optionIndex(this.accountID)).value(this.accountName(this.accountID))
            .layoutWeight(1).height(this.expandedDetails ? 40 : 32).font({ size: 13 })
            .onSelect((index: number) => { this.accountID = this.eligibleAccounts()[index].id; this.editorOpen = true; })
        }.width('100%')
        if (this.special()) {
          Row({ space: 8 }) {
            Text(this.categoryKey === 'income_fund_redemption' ? '基金账户' : '付款账户').fontSize(12).fontColor(AppColors.muted).width(64)

          Select(this.accountOptions(true)).selected(this.optionIndex(this.paymentID, true)).value(this.accountName(this.paymentID))
              .layoutWeight(1).height(this.expandedDetails ? 40 : 32).font({ size: 13 })
              .onSelect((index: number) => { this.paymentID = this.eligibleAccounts(true)[index].id; this.editorOpen = true; })
          }.width('100%')
        }
      }
      TextInput({ text: this.title, placeholder: '备注' }).height(this.expandedDetails ? 40 : 32).fontSize(14)
        .onChange((value: string) => { this.title = value; this.editorOpen = true; })
      if (debt(this.ledger.assets.find((a: Asset) => a.id === this.accountID)?.kind || '') && this.kind === 'expense' && !this.special()) {
        TextInput({ text: this.installments, placeholder: '分期期数（可选）' }).height(this.expandedDetails ? 40 : 32).fontSize(14).type(InputType.Number)
          .onChange((value: string) => { this.installments = value; })
        Text('分期时填写每期金额').fontSize(11).fontColor(AppColors.muted)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder private entryActions() {
      Button(this.editingID ? '保存修改' : '确认记账').width('100%').height(38).backgroundColor(AppColors.primary).fontColor(AppColors.onPrimary)
        .enabled(!this.busy && this.ready && this.ledger.assets.length > 0).onClick(() => { this.save(); })
      if (this.editingID) {
        Button('删除这笔账').fontColor(AppColors.danger).backgroundColor(AppColors.dangerTint)
          .onClick(() => { const t = this.ledger.transactions.find((item: Transaction) => item.id === this.editingID); if (t) this.remove(t); })
      }
  }
  @Builder private entryEditor() {
    Column({ space: 6 }) {
      this.entryHeader()
      this.entryTypes()
      TextInput({ text: this.amount, placeholder: '0.00' }).type(InputType.NUMBER_DECIMAL).fontSize(28).height(44)
        .onChange((value: string) => { this.amount = value; this.editorOpen = true; })
      this.entryFields()
      this.entryActions()
    }.padding(10).borderRadius(8).backgroundColor(AppColors.surface).width('100%').alignItems(HorizontalAlign.Start)
  }
  private pressAmountKey(key: string): void {
    this.amount = keypadAmount(this.amount, key);
    this.editorOpen = true;
  }
  @Builder private expandedEntry() {
    Row({ space: 16 }) {
      Scroll() {
        Column({ space: 16 }) {
          this.entryHeader()
          this.entryFields()
        }.padding(16).width('100%').borderRadius(8).backgroundColor(AppColors.surface)
      }.width(0).layoutWeight(1).height('100%').scrollBar(BarState.Off).edgeEffect(EdgeEffect.None)
      Column({ space: 10 }) {
        this.entryTypes()
        Row({ space: 8 }) {
          Text('¥').fontSize(24).fontColor(AppColors.muted)
          Text(this.amount || '0.00').fontSize(36).fontWeight(FontWeight.Medium).fontColor(AppColors.ink)
            .layoutWeight(1).maxLines(1).minFontSize(20).maxFontSize(36).textAlign(TextAlign.End)
        }.width('100%').height(54).padding({ left: 12, right: 12 }).backgroundColor(AppColors.surface).borderRadius(8)
        Row() {
          Text('金额').fontSize(12).fontColor(AppColors.muted).layoutWeight(1)
          Button('清空').height(28).fontSize(12).fontColor(AppColors.muted).backgroundColor(Color.Transparent)
            .onClick(() => { this.pressAmountKey('clear'); })
        }.width('100%')
        Grid() {
          ForEach(['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0', '⌫'], (key: string) => {
            GridItem() {
              Button(key, { type: ButtonType.Normal }).width('100%').height('100%').fontSize(25)
                .fontColor(AppColors.ink).backgroundColor(AppColors.surface).borderRadius(12)
                .accessibilityText(key === '⌫' ? '退格' : key === '.' ? '小数点' : key)
                .onClick(() => { this.pressAmountKey(key === '⌫' ? 'backspace' : key); })
            }
          }, (key: string) => key)
        }.columnsTemplate('1fr 1fr 1fr').rowsTemplate('1fr 1fr 1fr 1fr').rowsGap(8).columnsGap(8)
          .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        this.entryActions()
      }.width(0).layoutWeight(1).height('100%')
    }.width('100%').layoutWeight(1).padding({ top: 6, bottom: 6 }).alignItems(VerticalAlign.Top).enabled(!this.busy)
  }

  @Builder private dashboardCharts() {
    Column({ space: 12 }) {
      this.assetOverviewCard()
      this.overviewCard()
      this.weeklyChart()
      this.categoryChart('income')
      this.categoryChart('expense')
    }.width('100%')
  }
  @Builder private expandedOverview() {
    Row({ space: 16 }) {
      Scroll() { this.dashboardCharts() }.width(0).layoutWeight(1).height('100%').scrollBar(BarState.Off)
      Column({ space: 10 }) {
        Row() {
          Text('近期账目').fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.ink).layoutWeight(1)
          Text('最近 7 天').fontSize(13).fontColor(AppColors.muted)
        }.width('100%')
        if (this.recentDayCount === 0) {
          Text('这段时间暂无账目').fontSize(14).fontColor(AppColors.muted).padding(20)
        }
        List({ space: 4, scroller: this.recentDayScroller }) {
          LazyForEach(this.recentDaySource, (row: TransactionRowSnapshot) => {
            ListItem() {
              Column({ space: 4 }) {
                if (row.dateHeading) {
                  Text(row.dateHeading).fontSize(13).fontColor(AppColors.muted).width('100%').padding({ top: 8, bottom: 4 })
                }
                this.transactionRow(row.transaction)
              }.width('100%')
            }
          }, (row: TransactionRowSnapshot) => row.renderKey)
        }.layoutWeight(1).width('100%').cachedCount(6).scrollBar(BarState.Off)
      }.width(0).layoutWeight(1).height('100%')
    }.width('100%').layoutWeight(1).padding({ top: 6, bottom: 6 }).alignItems(VerticalAlign.Top).enabled(!this.busy)
  }

  @Builder private ledgerPage() {
      Column({ space: 12 }) {
        if (this.page === 0) {
          this.assetOverviewCard()
          this.overviewCard()
          this.weeklyChart()
          this.categoryChart('income')
          this.categoryChart('expense')
        }
        Row() {
          Text(this.page === 0 ? '最近账目' : '账目明细').fontSize(18).fontWeight(FontWeight.Bold).fontColor(AppColors.primary).layoutWeight(1)
          if (this.page === 0) {
            Button('查看全部').height(30).fontSize(12).fontColor(AppColors.accent).backgroundColor(Color.Transparent).onClick(() => { this.page = 1; this.search = ''; })
          }
        }.width('100%')
        this.transactionList()
      }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private chartColor(index: number): string {
    return ['#0969DA', '#1A7F37', '#8250DF', '#BF8700', '#CF222E', '#0891B2', '#DB61A2', '#6E7781'][index % 8];
  }
  private holdingTotal(fund: boolean): number { return fund ? this.cachedFunds : this.cachedHoldings; }
  private debtTotal(): number { return this.cachedDebt; }
  private repaymentTotal(): number { return this.cachedRepayment; }
  private axisRatio(value: number): number {
    const scale = Math.max(1, this.debtTotal(), this.holdingTotal(false) + this.holdingTotal(true));
    return Math.min(100, Math.max(0, value / scale * 100));
  }
  private barHeight(value: number): number {
    return Math.min(90, Math.max(0, value / this.dailyScale() * 90));
  }
  private dailyScale(): number {
    return this.cachedScale;
  }
  @Builder private assetOverviewCard() {
    Column({ space: 8 }) {
      Text('净资产').fontSize(12).fontColor(AppColors.muted)
      Text(this.display(this.netAssets())).fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.amountColor(this.netAssets()))
      Row({ space: 0 }) {
        Row() {
          Column() {}.height(10).width(`${this.axisRatio(this.debtTotal())}%`).backgroundColor(AppColors.danger).borderRadius(3)
        }.layoutWeight(1).justifyContent(FlexAlign.End).clip(true)
        Column() {}.width(2).height(16).backgroundColor(AppColors.ink)
        Row({ space: 0 }) {
          Column() {}.height(10).width(`${this.axisRatio(this.holdingTotal(false))}%`).backgroundColor(AppColors.success)
          Column() {}.height(10).width(`${this.axisRatio(this.holdingTotal(true))}%`).backgroundColor(AppColors.muted).borderRadius(3)
        }.layoutWeight(1).clip(true)
      }.width('100%').clip(true)
      Flex({ wrap: FlexWrap.Wrap }) {
        Text(`余额 ${this.display(this.holdingTotal(false))}`).fontSize(12).fontColor(AppColors.success).margin({ right: 12 })
        Text(`基金 ${this.display(this.holdingTotal(true))}`).fontSize(12).fontColor(AppColors.muted).margin({ right: 12 })
        Text(`负债 ${this.display(this.debtTotal())}`).fontSize(12).fontColor(AppColors.danger)
      }
      Text(`本月待还 ${this.display(this.repaymentTotal())}`).fontSize(13).fontColor(AppColors.ink)
    }.padding(14).width('100%').backgroundColor(AppColors.surface).borderRadius(8).alignItems(HorizontalAlign.Start)
  }
  private chartItems(kind: string): CategoryTotal[] { return kind === 'income' ? this.cachedIncome : this.cachedExpense; }
  @Builder private categoryChart(kind: string) {
    Column({ space: 10 }) {
      Text(kind === 'income' ? '收入分类占比' : '支出分类占比').fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppColors.ink)
      if (this.chartItems(kind).length === 0) {
        Text('暂无数据').fontSize(13).fontColor(AppColors.muted).padding(16)
      } else {
        Column({ space: 8 }) {
          CategoryRing({ items: this.chartItems(kind) })
            .accessibilityText(`${kind === 'income' ? '收入' : '支出'}分类环形图`)
          Column({ space: 6 }) {
            ForEach(this.chartItems(kind), (item: CategoryTotal, index: number) => {
              Row({ space: 5 }) {
                Circle().width(6).height(6).fill(this.chartColor(index))
                Text(item.name).fontSize(11).fontColor(AppColors.ink).layoutWeight(1).maxLines(1)
                Text(this.display(item.cents)).fontSize(11).fontColor(AppColors.muted)
              }.width('100%')
            }, (item: CategoryTotal) => `${this.month}-${kind}-${item.name}-${item.cents}`)
          }.width('100%')
        }.width('100%').alignItems(HorizontalAlign.Center)
      }
    }.padding(12).width('100%').borderRadius(8).backgroundColor(AppColors.surface).alignItems(HorizontalAlign.Start)
  }
  @Builder private weeklyChart() {
    Column({ space: 8 }) {
      Row() {
        Text('近 7 天收支').fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppColors.ink).layoutWeight(1)
        Text('收入').fontSize(11).fontColor(AppColors.success).margin({ right: 10 })
        Text('支出').fontSize(11).fontColor(AppColors.danger)
      }.width('100%')
      Text(`最高 ${this.display(this.dailyScale() === 1 ? 0 : this.dailyScale())}`).fontSize(10).fontColor(AppColors.muted)
      Row({ space: 8 }) {
        ForEach(this.cachedFlows, (day: DailyFlow) => {
          Column({ space: 5 }) {
            Row({ space: 3 }) {
              Column() {}.width(10).height(this.barHeight(day.income)).backgroundColor(AppColors.success).borderRadius(3)
              Column() {}.width(10).height(this.barHeight(day.expense)).backgroundColor(AppColors.danger).borderRadius(3)
            }.height(90).clip(true).alignItems(VerticalAlign.Bottom)
            Text(`${day.day}日`).fontSize(10).fontColor(AppColors.muted)
          }.layoutWeight(1).accessibilityText(`${day.day}日 收入${this.display(day.income)} 支出${this.display(day.expense)}`)
        }, (day: DailyFlow) => `${this.month}-${day.day}-${day.income}-${day.expense}-${this.dailyScale()}`)
      }.width('100%')
    }.padding(12).width('100%').backgroundColor(AppColors.surface).borderRadius(8).alignItems(HorizontalAlign.Start)
  }
  private orderedAssets(): Asset[] {
    return this.ledger.assets.filter((a: Asset) => a.kind === 'fund').concat(this.ledger.assets.filter((a: Asset) => a.kind !== 'fund' && !debt(a.kind)), this.ledger.assets.filter((a: Asset) => debt(a.kind)));
  }
  @Builder private assetsPage() {
    Column({ space: 16 }) {
      Text(`净资产 ${this.display(this.netAssets())}`).fontSize(27).fontWeight(FontWeight.Bold).fontColor(this.amountColor(this.netAssets()))
      if (this.initializationMode) {
      Button('＋ 添加账户').backgroundColor(AppColors.primary).fontColor(AppColors.onPrimary).onClick(() => {
        this.assetEditing = true; this.assetID = ''; this.assetName = ''; this.assetBalance = '0.00'; this.assetKindIndex = 0;
      })
      }
      if (this.initializationMode && this.assetEditing) {
        Column({ space: 12 }) {
          TextInput({ text: this.assetName, placeholder: '账户名称' }).onChange((value: string) => { this.assetName = value; })
          Select(this.assetOptions()).selected(this.assetKindIndex).value(ASSET_NAMES[this.assetKindIndex]).enabled(!this.assetID)
            .onSelect((index: number) => { this.assetKindIndex = index; })
          Text(this.assetID && ASSET_KINDS[this.assetKindIndex] === 'fund' ? '当前基金市值' : '期初余额').fontSize(12).fontColor(AppColors.muted)
          TextInput({ text: this.assetBalance, placeholder: '期初余额' }).onChange((value: string) => { this.assetBalance = value; })
          if (this.assetID && ASSET_KINDS[this.assetKindIndex] === 'fund') {
            TextInput({ text: this.fundCostInput, placeholder: '持有成本' }).height(34).onChange((v: string) => { this.fundCostInput = v; })
          }
          Row({ space: 12 }) {
            Button('保存账户').backgroundColor(AppColors.primary).fontColor(AppColors.onPrimary).onClick(() => { this.saveAsset(); })
            Button('取消').fontColor(AppColors.muted).backgroundColor(AppColors.secondarySurface).onClick(() => { this.assetEditing = false; })
          }
        }.padding(12).backgroundColor(AppColors.surface).borderRadius(8).width('100%')
      }
      if (this.windowWidth >= 700) {
        Row({ space: 16 }) {
          Column() { this.assetGroup(false) }.width(0).layoutWeight(1)
          Column() { this.assetGroup(true) }.width(0).layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      } else {
        Column({ space: 12 }) {
          ForEach(this.orderedAssets(), (asset: Asset) => {
            this.assetCard(asset, this.selectedAccount(asset.id))
          }, (asset: Asset) => asset.id)
        }.width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  private groupedAssets(liabilities: boolean): Asset[] {
    return this.orderedAssets().filter((asset: Asset) => debt(asset.kind) === liabilities);
  }
  @Builder private assetGroup(liabilities: boolean) {
    Column({ space: 12 }) {
      Column({ space: 4 }) {
        Text(liabilities ? '负债' : '资产').fontSize(14).fontColor(liabilities ? AppColors.danger : AppColors.success)
        Text(this.display(liabilities ? this.cachedDebt : this.cachedHoldings + this.cachedFunds))
          .fontSize(24).fontWeight(FontWeight.Bold).fontColor(liabilities ? AppColors.danger : AppColors.success)
          .maxLines(1).minFontSize(16).maxFontSize(24)
      }.width('100%').padding(12).borderRadius(8).backgroundColor(AppColors.surface).alignItems(HorizontalAlign.Start)
      if (this.groupedAssets(liabilities).length === 0) {
        Text(liabilities ? '暂无负债账户' : '暂无资产账户').fontSize(13).fontColor(AppColors.muted).padding(16)
      }
      ForEach(this.groupedAssets(liabilities), (asset: Asset) => {
        this.assetCard(asset, this.selectedAccount(asset.id))
      }, (asset: Asset) => asset.id)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder private assetCard(asset: Asset, index: number) {
        Column({ space: 10 }) {
          Row() {
            Column({ space: 5 }) {
              Text(asset.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppColors.primary)
              Text(ASSET_NAMES[ASSET_KINDS.indexOf(asset.kind)] || asset.kind).fontSize(12).fontColor(AppColors.muted)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text(this.display(debt(asset.kind) ? this.totalDebt(asset, this.assetValue(index)) : this.assetValue(index)))
              .fontSize(21).fontColor(debt(asset.kind) ? AppColors.danger : this.amountColor(this.assetValue(index)))
            if (this.initializationMode) {
            Button('编辑').fontSize(11).fontColor(AppColors.primary).backgroundColor(AppColors.secondarySurface).margin({ left: 10 })
              .onClick(() => { this.editAsset(asset); })
            }
          }.width('100%')
          if (debt(asset.kind)) {
            ForEach(repaymentRows(asset, this.expandedDebt === asset.id), (r: Repayment) => {
              Text(`${r.monthOffset === 0 ? '本月' : r.monthOffset === 1 ? '下月' : `${r.monthOffset} 个月后`}待还 ${this.display(cents(r.amount))}`).fontSize(12).fontColor(AppColors.muted)
            }, (r: Repayment) => r.id)
            Button(this.expandedDebt === asset.id ? '收起还款计划' : '查看还款计划').height(28).fontSize(12).fontColor(AppColors.accent).backgroundColor(Color.Transparent)
              .onClick(() => { this.expandedDebt = this.expandedDebt === asset.id ? '' : asset.id; })
          }
          if (asset.kind === 'fund') {
            Text(`成本 ${this.display(cents(asset.fundCost || '0'))} · 累计盈亏 ${this.display(cents(asset.fundMarketValue || asset.balance) - cents(asset.fundCost || '0'))}`)
              .fontSize(12).fontColor(AppColors.muted)
            ForEach(asset.fundActivities.slice(0, 5), (record: FundActivity) => {
              Text(`${new Date(record.occurredAt).toLocaleDateString()} · ${record.kind === 'valuation' ? '盈亏' : '投入/定投'} ${this.display(cents(record.amount))}`).fontSize(12).fontColor(AppColors.muted)
            }, (record: FundActivity) => record.id)
          }
        }.padding(12).backgroundColor(AppColors.surface).borderRadius(8).width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder private settingsControls() {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Text('初始化数据').fontSize(16).fontColor(AppColors.ink).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.initializationMode })
          .onChange((enabled: boolean) => { this.initializationMode = enabled; this.assetEditing = false; })
      }.width('100%').padding(16).backgroundColor(AppColors.surface).borderRadius(8)

      Column({ space: 8 }) {
        Text('备份').fontSize(19).fontWeight(FontWeight.Bold).fontColor(AppColors.ink)
        Button('导出备份').height(36).width('100%').backgroundColor(AppColors.primary).fontColor(AppColors.onPrimary).onClick(() => { this.exportFile(); })
        Button('导入备份').height(36).width('100%').fontColor(AppColors.accent).backgroundColor(AppColors.secondarySurface).onClick(() => { this.importFile(); })
      }.width('100%').padding(12).borderRadius(8).backgroundColor(AppColors.surface).alignItems(HorizontalAlign.Start)
      if (this.expandedDetails) {
        Column({ space: 8 }) {
          Button('深色模式 · 即将开放').height(38).width('100%').fontColor(AppColors.muted).backgroundColor(AppColors.secondarySurface)
            .onClick(() => { this.notify('深色模式切换稍后开放'); })
          Button('隐藏功能 · 即将开放').height(38).width('100%').fontColor(AppColors.muted).backgroundColor(AppColors.secondarySurface)
            .onClick(() => { this.notify('隐藏功能稍后开放'); })
        }.padding(12).width('100%').backgroundColor(AppColors.surface).borderRadius(8)
      }
    }.width('100%')
  }
  @Builder private categorySettings() {
    Column({ space: 10 }) {
      Column({ space: 8 }) {
        Text('添加分类').fontSize(19).fontWeight(FontWeight.Bold).fontColor(AppColors.primary)
        TextInput({ text: this.categoryName, placeholder: this.expandedDetails ? '例如：日常开销（默认支出）' : '分类名称' }).height(36).onChange((value: string) => { this.categoryName = value; })
        Select([{ value: '支出分类' }, { value: '收入分类' }]).selected(this.categoryKind === 'expense' ? 0 : 1)
          .value(this.categoryKind === 'expense' ? '支出分类' : '收入分类').onSelect((index: number) => { this.categoryKind = index === 0 ? 'expense' : 'income'; })
        Button('添加').height(34).backgroundColor(AppColors.primary).fontColor(AppColors.onPrimary).onClick(() => { this.addCategory(); })
      }.width('100%').padding(12).borderRadius(8).backgroundColor(AppColors.surface).alignItems(HorizontalAlign.Start)
      if (this.expandedDetails) {
        Row({ space: 6 }) {
          ForEach(['日常开销', '宠物', '旅行'], (name: string) => {
            Button(name).fontSize(12).height(30).fontColor(AppColors.accent).backgroundColor(AppColors.accentTint)
              .onClick(() => { this.categoryName = name; })
          })
        }.width('100%')
        Column({ space: 8 }) {
          Text('已有分类').fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.ink)
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.ledger.categories.filter((category: Category) => category.kind === this.categoryKind), (category: Category) => {
              Row({ space: 6 }) {
                Image(CategoryStyle.icon(category.presetKey)).width(18).height(18)
                Text(category.name).fontSize(12).fontColor(AppColors.ink)
              }.padding(8).margin({ right: 6, bottom: 6 }).backgroundColor(AppColors.secondarySurface).borderRadius(8)
            }, (category: Category) => category.id)
          }.width('100%')
        }.padding(12).width('100%').backgroundColor(AppColors.surface).borderRadius(8).alignItems(HorizontalAlign.Start)
      }
    }.width('100%')
  }
  @Builder private settingsPage() {
    if (this.expandedDetails) {
      Row({ space: 16 }) {
        Column() { this.categorySettings() }.width(0).layoutWeight(1)
        Column() { this.settingsControls() }.width(0).layoutWeight(1)
      }.width('100%').alignItems(VerticalAlign.Top)
    } else {
      Column({ space: 10 }) {
        this.settingsControls()
        this.categorySettings()
      }.width('100%')
    }
  }

  @Builder private monthSelector() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        Text(this.monthLabel()).fontSize(15).fontWeight(FontWeight.Medium).fontColor(AppColors.ink)
        Image($r('app.media.chevron_down')).width(13).height(13)
      }
    }.height(36).padding({ left: 14, right: 14 }).borderRadius(8).backgroundColor(AppColors.surface)
      .enabled(this.ready && !this.busy).accessibilityText(`选择年月，${this.monthLabel()}`)
      .onClick(() => { this.selectMonth(); })
  }

  build() {
    Column({ space: 0 }) {
      if ((this.page === 1 && !this.expandedDetails) || this.busy) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.page === 1 && !this.expandedDetails) { this.monthSelector() }
          if (this.busy) {
            Row() { LoadingProgress().width(20).height(20).color(AppColors.accent) }.width('100%')
          }
        }.height(44).width('100%')
      }
      if (!this.ready) {
        if (this.startupError) {
          Text(this.startupError).fontSize(15).fontColor(AppColors.danger).padding(24)
        } else {
          LoadingProgress().width(32).height(32).color(AppColors.accent).margin(24)
        }
      } else if (this.page === 2 && this.expandedDetails) {
        this.expandedEntry()
      } else if (this.page === 0 && this.expandedDetails) {
        this.expandedOverview()
      } else if (this.page === 1) {
        this.detailsPage()
      } else {
        Scroll(this.pageScroller) {
          Column() {
            if (this.page <= 1) { this.ledgerPage() }
            else if (this.page === 2) {
              this.entryEditor()
            }
            else if (this.page === 3) { this.assetsPage() }
            else { this.settingsPage() }
          }.width('100%').padding({ top: 6, bottom: this.page === 2 || this.page === 4 ? 6 : 24 })
        }.layoutWeight(1).scrollBar(BarState.Off).edgeEffect(EdgeEffect.None).width('100%').enabled(!this.busy)
      }
      this.nav()
    }.width('100%').height('100%').padding({ left: 20, right: 20 }).backgroundColor(AppColors.background)
      .onAreaChange((oldArea: Area, newArea: Area) => { this.windowWidth = Number(newArea.width);
        const expanded = this.windowWidth >= 700;
        if (expanded !== this.expandedDetails) this.expandedDetails = expanded; })
  }
}
