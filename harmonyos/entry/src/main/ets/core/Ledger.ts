// Platform independent rules, preserving the Swift version-2 JSON contract.
export interface Category {
  id: string; presetKey: string; name: string; kind: string;
  symbolName: string; sortOrder: number; isSystemPreset: boolean;
}
export interface Repayment { id: string; monthOffset: number; amount: string; }
export interface Adjustment { monthOffset: number; amount: number; }
export interface FundActivity { id: string; kind: string; amount: string; occurredAt: string; note: string; }
export interface Asset {
  id: string; name: string; kind: string; balance: string; repayments: Repayment[];
  fundCost?: string; fundMarketValue?: string; fundActivities: FundActivity[];
}
export interface Transaction {
  id: string; kind: string; title: string; categoryPresetKey: string;
  accountID?: string; accountName: string; accountKind?: string; accountSymbolName?: string;
  paymentAccountID?: string; paymentAccountName?: string; paymentAccountKind?: string;
  paymentAccountSymbolName?: string; amount: string; installmentMonths?: number;
  repaymentAdjustments?: Adjustment[]; occurredAt: string;
}
export interface Ledger {
  version: number; exportedAt: string; categories: Category[]; assets: Asset[]; transactions: Transaction[];
}
export interface AmountCandidate { amount: string; score: number; kind: string; }
export interface Overview { income: number; expense: number; net: number; }
export interface CategoryTotal { name: string; cents: number; }
export const ASSET_KINDS: string[] = ['cash', 'debitCard', 'creditCard', 'alipay', 'alipayYuEBao',
  'alipayCredit', 'wechatPay', 'wechatChangePass', 'wechatCredit', 'meituan', 'jd', 'fund'];
export const ASSET_NAMES: string[] = ['现金', '借记卡', '信用卡', '支付宝余额', '余额宝', '花呗',
  '零钱', '零钱通', '微信分付', '美团月付', '京东白条', '基金'];
export function debt(kind: string): boolean {
  return ['creditCard', 'alipayCredit', 'wechatCredit', 'meituan', 'jd'].includes(kind);
}
export function cents(raw: string): number {
  if (typeof raw !== 'string' || !/^-?\d+(\.\d{1,2})?$/.test(raw.trim())) {
    throw new Error('金额必须是最多两位小数的数字');
  }
  const value = raw.trim();
  const negative = value.startsWith('-');
  const parts = value.replace('-', '').split('.');
  const result = Number(parts[0]) * 100 + Number((parts[1] || '').padEnd(2, '0'));
  if (!Number.isSafeInteger(result) || result > 9000000000000) throw new Error('金额超出支持范围');
  return negative ? -result : result;
}
export function money(value: number): string {
  if (!Number.isSafeInteger(value)) throw new Error('金额计算超出安全范围');
  const absolute = Math.abs(value);
  return `${value < 0 ? '-' : ''}${Math.floor(absolute / 100)}.${String(absolute % 100).padStart(2, '0')}`;
}
export function clone(ledger: Ledger): Ledger { return JSON.parse(JSON.stringify(ledger)) as Ledger; }
function recordID(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (part: string) => {
    const value = Math.floor(Math.random() * 16);
    return (part === 'x' ? value : (value & 3) | 8).toString(16);
  });
}
export function emptyLedger(): Ledger {
  const expense = ['food:餐饮', 'transport:交通', 'repayment:还款', 'fund_purchase:购买基金', 'daily:日用',
    'shopping:购物', 'subscription:订阅', 'entertainment:娱乐', 'health:医疗', 'education:学习', 'family:家庭', 'other:其他支出'];
  const income = ['salary:工资', 'bonus:奖金', 'freelance:副业', 'investment:投资收益', 'fund_redemption:基金赎回',
    'interest:利息', 'reimbursement:报销', 'refund:退款', 'transfer_in:转入调整', 'gift:礼金', 'sale:闲置出售', 'other:其他收入'];
  const categories: Category[] = [];
  [expense, income].forEach((items: string[], group: number) => items.forEach((item: string, index: number) => {
    const parts = item.split(':');
    const kind = group === 0 ? 'expense' : 'income';
    categories.push({ id: `00000000-0000-4000-8000-${String(group * 100 + index).padStart(12, '0')}`, presetKey: `${kind}_${parts[0]}`,
      name: parts[1], kind: kind, symbolName: 'tag.fill', sortOrder: index * 10, isSystemPreset: true });
  }));
  categories.push({ id: 'A81E0D7F-4088-40F7-A6A5-7A634FE6C0FA', presetKey: 'expense_transfer',
    name: '转账/提现', kind: 'expense', symbolName: 'arrow.left.arrow.right.circle.fill', sortOrder: 24, isSystemPreset: true });
  return { version: 2, exportedAt: new Date().toISOString(), categories: categories, assets: [], transactions: [] };
}
export function newAsset(id: string, name: string, kind: string, balance: string): Asset {
  if (!name.trim()) throw new Error('请填写账户名称');
  if (!ASSET_KINDS.includes(kind)) throw new Error('不支持的账户类型');
  const repayments: Repayment[] = [];
  for (let i = 0; i <= 24; i++) repayments.push({ id: recordID(), monthOffset: i, amount: '0.00' });
  const asset: Asset = { id: id, name: name.trim(), kind: kind, balance: money(cents(balance)), repayments: repayments, fundActivities: [] };
  if (kind === 'fund') { asset.fundCost = asset.balance; asset.fundMarketValue = asset.balance; }
  return asset;
}
export function balances(ledger: Ledger): number[] {
  const values = ledger.assets.map((a: Asset) => cents(a.balance));
  const applyExpense = (id: string, amount: number): void => {
    const i = ledger.assets.findIndex((a: Asset) => a.id === id);
    if (i >= 0) values[i] += debt(ledger.assets[i].kind) ? amount : -amount;
  };
  ledger.transactions.forEach((t: Transaction) => {
    const i = ledger.assets.findIndex((a: Asset) => a.id === t.accountID);
    if (i < 0 || t.kind === 'fundProfit') return;
    const amount = cents(t.amount);
    if (t.kind === 'transfer') {
      validateTransfer(ledger, t);
      // Apple v2: accountID receives money; paymentAccountID sends money.
      applyExpense(t.paymentAccountID as string, amount);
      values[i] += amount;
      return;
    }
    if (t.categoryPresetKey === 'expense_fund_purchase' && t.paymentAccountID) {
      applyExpense(t.paymentAccountID, amount); return;
    }
    if (debt(ledger.assets[i].kind)) {
      values[i] += t.kind === 'income' || t.categoryPresetKey === 'expense_repayment' ? -amount : amount;
      if (t.categoryPresetKey === 'expense_repayment' && t.paymentAccountID) applyExpense(t.paymentAccountID, amount);
    } else {
      values[i] += t.kind === 'income' ? amount : -amount;
    }
  });
  values.forEach((value: number) => { if (!Number.isSafeInteger(value)) throw new Error('账户余额超出安全范围'); });
  return values;
}
export function overview(ledger: Ledger, month: string): Overview {
  let income = 0; let expense = 0;
  ledger.transactions.filter((t: Transaction) => localMonth(t.occurredAt) === month).forEach((t: Transaction) => {
    if (excludedFromStatistics(t)) return;
    if (t.kind === 'income') income += cents(t.amount);
    if (t.kind === 'expense') expense += cents(t.amount);
  });
  return { income: income, expense: expense, net: income - expense };
}
export function localMonth(iso: string): string {
  const date = new Date(iso);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}
export function categoryTotals(ledger: Ledger, month: string, kind: string = 'expense'): CategoryTotal[] {
  return ledger.categories.filter((c: Category) => c.kind === kind).map((c: Category) => {
    const value = ledger.transactions.filter((t: Transaction) => t.kind === kind && !excludedFromStatistics(t) && t.categoryPresetKey === c.presetKey && localMonth(t.occurredAt) === month)
      .reduce((sum: number, t: Transaction) => sum + cents(t.amount), 0);
    return { name: c.name, cents: value };
  }).filter((c: CategoryTotal) => c.cents > 0).sort((a: CategoryTotal, b: CategoryTotal) => b.cents - a.cents);
}
function excludedFromStatistics(t: Transaction): boolean {
  return t.kind === 'transfer' || ['expense_transfer', 'expense_repayment', 'expense_fund_purchase',
    'income_fund_redemption', 'income_transfer_in'].includes(t.categoryPresetKey);
}
function validateTransfer(ledger: Ledger, t: Transaction): void {
  if ((t.kind === 'transfer') !== (t.categoryPresetKey === 'expense_transfer'))
    throw new Error('转账账目与分类不匹配');
  if (t.kind !== 'transfer') return;
  const destination = ledger.assets.find((a: Asset) => a.id === t.accountID);
  const source = ledger.assets.find((a: Asset) => a.id === t.paymentAccountID);
  if (!destination || !source || source.id === destination.id ||
    debt(source.kind) || debt(destination.kind) || source.kind === 'fund' || destination.kind === 'fund')
    throw new Error('转出账户和转入账户必须是两个不同的余额账户');
}
function adjustFund(asset: Asset, amount: number): void {
  asset.fundCost = money(cents(asset.fundCost ?? '0') + amount);
  asset.fundMarketValue = money(cents(asset.fundMarketValue ?? '0') + amount);
  asset.balance = asset.fundMarketValue;
}
function applyEffects(ledger: Ledger, t: Transaction, reverse: boolean): void {
  const asset = ledger.assets.find((a: Asset) => a.id === t.accountID);
  if (!asset) throw new Error('找不到账目对应账户');
  const sign = reverse ? -1 : 1;
  const amount = cents(t.amount);
  if (t.categoryPresetKey === 'expense_fund_purchase') adjustFund(asset, sign * amount);
  if (t.categoryPresetKey === 'income_fund_redemption') {
    const fund = ledger.assets.find((a: Asset) => a.id === t.paymentAccountID);
    if (!fund) throw new Error('找不到基金账户');
    adjustFund(fund, -sign * amount);
  }
  if (t.kind !== 'expense' || !debt(asset.kind)) return;
  if (!reverse) {
    const changes: Adjustment[] = [];
    if (t.categoryPresetKey === 'expense_repayment') {
      let remaining = amount;
      asset.repayments.sort((a: Repayment, b: Repayment) => a.monthOffset - b.monthOffset).forEach((r: Repayment) => {
        const paid = Math.min(Math.max(cents(r.amount), 0), remaining);
        if (paid > 0) changes.push({ monthOffset: r.monthOffset, amount: -paid / 100 });
        remaining -= paid;
      });
    } else if (t.installmentMonths) {
      for (let i = 1; i <= t.installmentMonths; i++) changes.push({ monthOffset: i, amount: amount / 100 });
    } else changes.push({ monthOffset: 0, amount: amount / 100 });
    t.repaymentAdjustments = changes;
  }
  let changes = t.repaymentAdjustments || [];
  if (reverse && changes.length === 0) {
    if (t.categoryPresetKey === 'expense_repayment') changes = [{ monthOffset: 0, amount: -amount / 100 }];
    else if (t.installmentMonths) {
      for (let i = 1; i <= t.installmentMonths; i++) changes.push({ monthOffset: i, amount: amount / 100 });
    } else changes = [{ monthOffset: 0, amount: amount / 100 }];
  }
  changes.forEach((change: Adjustment) => {
    let repayment = asset.repayments.find((r: Repayment) => r.monthOffset === change.monthOffset);
    if (!repayment) {
      repayment = { id: recordID(), monthOffset: change.monthOffset, amount: '0.00' };
      asset.repayments.push(repayment);
    }
    repayment.amount = money(cents(repayment.amount) + sign * Math.round(change.amount * 100));
  });
}
export function saveTransaction(current: Ledger, input: Transaction): Ledger {
  const next = clone(current);
  const t = JSON.parse(JSON.stringify(input)) as Transaction;
  if (!['expense', 'income', 'transfer'].includes(t.kind)) throw new Error('请选择收入、支出或转账');
  const amount = cents(t.amount);
  if (amount <= 0) throw new Error('金额必须大于零');
  const category = next.categories.find((c: Category) => c.presetKey === t.categoryPresetKey && c.kind === (t.kind === 'transfer' ? 'expense' : t.kind));
  const asset = next.assets.find((a: Asset) => a.id === t.accountID);
  if (!category || !asset || !Number.isFinite(Date.parse(t.occurredAt))) throw new Error('请检查分类、账户和日期');
  validateTransfer(next, t);
  const special = ['expense_transfer', 'expense_repayment', 'expense_fund_purchase', 'income_fund_redemption'].includes(t.categoryPresetKey);
  if (special) {
    const payment = next.assets.find((a: Asset) => a.id === t.paymentAccountID);
    if (!payment || payment.id === asset.id) throw new Error('请选择另一个关联账户');
    if (t.categoryPresetKey === 'expense_repayment' && (!debt(asset.kind) || debt(payment.kind) || payment.kind === 'fund'))
      throw new Error('还款须选择负债账户和余额付款账户');
    if (t.categoryPresetKey === 'expense_fund_purchase' && (asset.kind !== 'fund' || debt(payment.kind) || payment.kind === 'fund'))
      throw new Error('购买基金须选择基金账户和余额付款账户');
    if (t.categoryPresetKey === 'income_fund_redemption' && (payment.kind !== 'fund' || debt(asset.kind) || asset.kind === 'fund'))
      throw new Error('基金赎回须选择余额收款账户和基金账户');
  } else {
    t.paymentAccountID = undefined; t.paymentAccountName = undefined;
    t.paymentAccountKind = undefined; t.paymentAccountSymbolName = undefined;
    if (asset.kind === 'fund') throw new Error('基金账户请使用购买基金或基金赎回');
  }
  if (t.installmentMonths && (!Number.isInteger(t.installmentMonths) || t.installmentMonths < 1 || t.installmentMonths > 24 || !debt(asset.kind) || t.kind !== 'expense' || special))
    throw new Error('分期仅支持负债账户的普通支出，期数为 1～24');
  const old = next.transactions.find((item: Transaction) => item.id === t.id);
  if (old) applyEffects(next, old, true);
  t.amount = money(amount); t.accountName = asset.name; t.accountKind = asset.kind;
  if (t.paymentAccountID) {
    const payment = next.assets.find((a: Asset) => a.id === t.paymentAccountID);
    if (payment) { t.paymentAccountName = payment.name; t.paymentAccountKind = payment.kind; }
  }
  applyEffects(next, t, false);
  next.transactions = next.transactions.filter((item: Transaction) => item.id !== t.id);
  next.transactions.push(t);
  next.transactions.sort((a: Transaction, b: Transaction) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt));
  balances(next);
  return next;
}
export function deleteTransaction(current: Ledger, id: string): Ledger {
  const next = clone(current);
  const old = next.transactions.find((t: Transaction) => t.id === id);
  if (!old) throw new Error('账目不存在');
  applyEffects(next, old, true);
  next.transactions = next.transactions.filter((t: Transaction) => t.id !== id);
  return next;
}
function text(value: unknown, label: string): string {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`备份的${label}无效`);
  return value;
}
export function parseBackup(raw: string): Ledger {
  if (raw.length > 20 * 1024 * 1024) throw new Error('备份超过 20 MB，请拆分后导入');
  const data = JSON.parse(raw) as Ledger;
  if (!data || data.version !== 2 || !Array.isArray(data.assets) || !Array.isArray(data.categories) || !Array.isArray(data.transactions))
    throw new Error('请选择苹果端导出的完整 version 2 JSON 备份');
  const next = clone(data);
  const ids = new Set<string>();
  const unique = (id: string): void => { if (ids.has(id)) throw new Error('备份包含重复 ID'); ids.add(id); };
  next.assets.forEach((a: Asset) => {
    text(a.id, '账户 ID'); text(a.name, '账户名称'); unique(a.id);
    if (!ASSET_KINDS.includes(a.kind)) throw new Error('备份包含未知账户类型');
    a.balance = money(cents(a.balance));
    if (a.fundCost !== undefined && a.fundCost !== null) a.fundCost = money(cents(a.fundCost));
    if (a.fundMarketValue !== undefined && a.fundMarketValue !== null) a.fundMarketValue = money(cents(a.fundMarketValue));
    if (!Array.isArray(a.repayments)) throw new Error('备份缺少还款计划');
    const offsets = new Set<number>();
    a.repayments.forEach((r: Repayment) => {
      text(r.id, '还款计划 ID');
      if (!Number.isInteger(r.monthOffset) || r.monthOffset < 0 || r.monthOffset > 24 || offsets.has(r.monthOffset)) throw new Error('还款计划月份无效');
      offsets.add(r.monthOffset); r.amount = money(cents(r.amount));
    });
    a.fundActivities = a.fundActivities || [];
    if (!Array.isArray(a.fundActivities)) throw new Error('基金活动格式无效');
    a.fundActivities.forEach((f: FundActivity) => {
      text(f.id, '基金活动 ID'); text(f.kind, '基金活动类型');
      f.amount = money(cents(f.amount));
      if (!Number.isFinite(Date.parse(f.occurredAt))) throw new Error('基金活动日期无效');
    });
  });
  ids.clear(); const keys = new Set<string>();
  next.categories.forEach((c: Category) => {
    text(c.id, '分类 ID'); unique(c.id); text(c.name, '分类名称'); text(c.presetKey, '分类标识');
    if (keys.has(c.presetKey) || !['expense', 'income'].includes(c.kind)) throw new Error('分类重复或类型无效');
    keys.add(c.presetKey);
  });
  ids.clear();
  next.transactions.forEach((t: Transaction, index: number) => {
    text(t.id, '账目 ID'); unique(t.id);
    if (!['expense', 'income', 'transfer', 'fundProfit'].includes(t.kind)) throw new Error(`第 ${index + 1} 笔账目的类型不支持`);
    if (t.kind !== 'fundProfit' && cents(t.amount) <= 0) throw new Error(`第 ${index + 1} 笔账目的金额必须大于零`);
    cents(t.amount);
    if (!Number.isFinite(Date.parse(t.occurredAt))) throw new Error('账目日期无效');
    if (!t.accountID) {
      const matches = next.assets.filter((a: Asset) => a.name === t.accountName && (!t.accountKind || a.kind === t.accountKind));
      if (matches.length !== 1) throw new Error('旧账目账户无法唯一匹配');
      t.accountID = matches[0].id;
    }
    if (!next.assets.some((a: Asset) => a.id === t.accountID)) throw new Error('账目引用的账户不存在');
    if (t.paymentAccountID && !next.assets.some((a: Asset) => a.id === t.paymentAccountID)) throw new Error('关联账户不存在');
    validateTransfer(next, t);
    if (t.kind !== 'fundProfit' && !next.categories.some((c: Category) => c.presetKey === t.categoryPresetKey && c.kind === (t.kind === 'transfer' ? 'expense' : t.kind)))
      throw new Error('账目引用的分类不存在或类型不匹配');
    if (t.installmentMonths != null && (!Number.isInteger(t.installmentMonths) || t.installmentMonths < 1 || t.installmentMonths > 24)) throw new Error('分期期数无效');
    if (t.repaymentAdjustments != null && !Array.isArray(t.repaymentAdjustments)) throw new Error('还款调整记录无效');
    (t.repaymentAdjustments || []).forEach((a: Adjustment) => {
      if (!Number.isInteger(a.monthOffset) || a.monthOffset < 0 || a.monthOffset > 24 || !Number.isFinite(a.amount) || Math.abs(a.amount * 100 - Math.round(a.amount * 100)) > 0.001)
        throw new Error('还款调整记录无效');
    });
  });
  balances(next);
  next.transactions.sort((a: Transaction, b: Transaction) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt));
  return next;
}
export function exportBackup(ledger: Ledger): string {
  const exported = clone(ledger); exported.exportedAt = new Date().toISOString();
  return JSON.stringify(exported, null, 2);
}
export function amountCandidates(raw: string): AmountCandidate[] {
  const candidates: AmountCandidate[] = [];
  const lines = raw.replace(/￥/g, '¥').split(/\n/);
  lines.forEach((line: string, index: number) => {
    const pattern = /(?:¥|RMB|CNY)?\s*([0-9]{1,9}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)(?![0-9])/g;
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(line)) !== null) {
      const value = match[1].replace(/,/g, '');
      if (cents(value) <= 0 || /订单号|手机号|卡号|验证码|积分|单号/.test(line)) continue;
      const context = `${lines[index - 1] || ''} ${line}`;
      if (/\d{1,2}:\d{2}|\d{4}[-/]\d/.test(line) && !/[¥]|实付|金额/.test(line)) continue;
      let score = /[¥]|RMB|CNY/.test(match[0]) ? 4 : 0;
      if (/实付|实际支付|实付款|付款金额|支付成功|收款金额/.test(context)) score += 8;
      else if (/合计|总计|金额|支付|付款|收入|退款/.test(context)) score += 4;
      if (/余额|优惠|原价|折扣|立减/.test(line)) score -= 6;
      if (value.includes('.')) score += 2;
      if (score > 0) candidates.push({ amount: money(cents(value)), score: score, kind: /退款|收入|收款/.test(context) ? 'income' : 'expense' });
    }
  });
  candidates.sort((a: AmountCandidate, b: AmountCandidate) => b.score - a.score);
  const seen = new Set<string>();
  return candidates.filter((c: AmountCandidate) => { if (seen.has(c.amount)) return false; seen.add(c.amount); return true; }).slice(0, 5);
}

// Swift AssetItem.fundCurrentValue is authoritative, independent of ledger balanceMap.
export function assetValues(ledger: Ledger): number[] {
  const result = balances(ledger);
  return ledger.assets.map((a: Asset, i: number) => a.kind === 'fund' ? cents(a.fundMarketValue ?? a.balance) : result[i]);
}
export function repaymentRows(asset: Asset, expanded: boolean): Repayment[] {
  return asset.repayments.filter((r: Repayment) => expanded || r.monthOffset === 1)
    .slice().sort((a: Repayment, b: Repayment) => a.monthOffset - b.monthOffset);
}
export function addFundActivity(current: Ledger, assetID: string, activity: FundActivity): Ledger {
  const next = clone(current);
  const asset = next.assets.find((a: Asset) => a.id === assetID && a.kind === 'fund');
  if (!asset) throw new Error('请选择基金账户');
  if (!['valuation', 'investment'].includes(activity.kind) || !Number.isFinite(Date.parse(activity.occurredAt)))
    throw new Error('基金记录类型或日期无效');
  const amount = cents(activity.amount);
  if (activity.kind === 'valuation') asset.fundMarketValue = money(cents(asset.fundMarketValue ?? '0') + amount);
  else {
    asset.fundCost = money(cents(asset.fundCost ?? '0') + amount);
    if (cents(asset.fundMarketValue ?? '0') === 0) asset.fundMarketValue = asset.fundCost;
  }
  asset.balance = asset.fundMarketValue ?? asset.balance;
  asset.fundActivities.unshift({ id: activity.id, kind: activity.kind, amount: money(amount), occurredAt: activity.occurredAt, note: activity.note.trim() });
  return next;
}
export interface DailyFlow { day: string; income: number; expense: number; }
export function dailyFlows(ledger: Ledger, month: string, now: Date = new Date()): DailyFlow[] {
  const parts = month.split('-').map(Number);
  const end = localMonth(now.toISOString()) === month ? new Date(now) : new Date(parts[0], parts[1], 0, 12);
  const result: DailyFlow[] = [];
  for (let offset = 6; offset >= 0; offset--) {
    const date = new Date(end); date.setDate(date.getDate() - offset);
    let income = 0; let expense = 0;
    ledger.transactions.filter((t: Transaction) => localMonth(t.occurredAt) === month && new Date(t.occurredAt).toDateString() === date.toDateString() && !excludedFromStatistics(t))
      .forEach((t: Transaction) => { if (t.kind === 'income') income += cents(t.amount); if (t.kind === 'expense') expense += cents(t.amount); });
    result.push({ day: String(date.getDate()), income: income, expense: expense });
  }
  return result;
}

export function calendarDay(month: string, requestedDay: number): number {
  const parts = month.split('-').map(Number);
  return Math.max(1, Math.min(requestedDay, new Date(parts[0], parts[1], 0).getDate()));
}
// Monday-first calendar, padded to complete weeks. Zero means an empty cell.
export function calendarCells(month: string): number[] {
  const parts = month.split('-').map(Number);
  const leading = (new Date(parts[0], parts[1] - 1, 1).getDay() + 6) % 7;
  const days = new Date(parts[0], parts[1], 0).getDate();
  const count = Math.ceil((leading + days) / 7) * 7;
  return Array.from({ length: count }, (_: unknown, index: number) => index >= leading && index < leading + days ? index - leading + 1 : 0);
}

export interface TransactionRowSnapshot {
  transaction: Transaction;
  dateHeading: string;
  renderKey: string;
}
// Each render callback owns its date grouping; it never indexes a newer filtered list.
export function transactionRows(transactions: Transaction[]): TransactionRowSnapshot[] {
  let previousDate = '';
  return transactions.map((original: Transaction) => {
    const transaction = JSON.parse(JSON.stringify(original)) as Transaction;
    const date = new Date(transaction.occurredAt);
    const key = date.toDateString();
    const heading = key === previousDate ? '' : date.toLocaleDateString();
    previousDate = key;
    return { transaction: transaction, dateHeading: heading,
      renderKey: JSON.stringify(transaction) + '|' + heading };
  });
}
