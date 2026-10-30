import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire, Module } from 'node:module';
import { test } from 'node:test';
const require = createRequire(import.meta.url);
const studio = process.env.DEVECO_HOME || '/Applications/DevEco-Studio.app/Contents';
const ts = require(path.join(studio, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = path.resolve(import.meta.dirname, '../entry/src/main/ets/core/Ledger.ts');
const options = { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, strict: true, skipLibCheck: true };
const program = ts.createProgram([source], options);
const diagnostics = ts.getPreEmitDiagnostics(program);
assert.equal(diagnostics.length, 0, diagnostics.map(d => ts.flattenDiagnosticMessageText(d.messageText, '\n')).join('\n'));
const output = ts.transpileModule(fs.readFileSync(source, 'utf8'), { compilerOptions: options }).outputText;
const loaded = new Module(source); loaded.filename = source; loaded.paths = [];
loaded._compile(output, source);
const L = loaded.exports;
const uuid = n => `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
const fixture = () => {
  const ledger = L.emptyLedger();
  ledger.assets = [L.newAsset(uuid(1), '现金', 'cash', '1000.00'),
    L.newAsset(uuid(2), '信用卡', 'creditCard', '0.00'), L.newAsset(uuid(3), '基金', 'fund', '200.00')];
  return ledger;
};
const transaction = (overrides = {}) => ({ id: uuid(10), kind: 'expense', title: '午饭',
  categoryPresetKey: 'expense_food', accountID: uuid(1), accountName: '现金', amount: '25.10',
  occurredAt: '2026-10-30T12:00:00+08:00', ...overrides });

test('金额用整数分计算，拒绝精度丢失、NaN、科学记数法及超额', () => {
  assert.equal(L.cents('0.10') + L.cents('0.20'), 30);
  assert.equal(L.money(-101), '-1.01');
  for (const raw of ['1.001', 'NaN', '1e3', '', '90000000001.00']) assert.throws(() => L.cents(raw));
});
test('普通支出、收入及修改与苹果端余额口径一致', () => {
  const initial = fixture();
  let next = L.saveTransaction(initial, transaction());
  assert.equal(L.balances(next)[0], 97490);
  assert.equal(L.balances(initial)[0], 100000, '保存不能提前改变原账本');
  next = L.saveTransaction(next, transaction({ amount: '40.00' }));
  assert.equal(L.balances(next)[0], 96000);
  next = L.saveTransaction(next, transaction({ id: uuid(11), kind: 'income', categoryPresetKey: 'income_salary', amount: '100.00' }));
  assert.equal(L.balances(next)[0], 106000);
  assert.equal(L.balances(L.deleteTransaction(next, uuid(10)))[0], 110000);
});
test('分期保留原版“每期金额”口径，编辑和删除撤销待还计划', () => {
  let next = L.saveTransaction(fixture(), transaction({ accountID: uuid(2), amount: '100', installmentMonths: 3 }));
  assert.deepEqual(next.assets[1].repayments.slice(1, 4).map(r => r.amount), ['100.00', '100.00', '100.00']);
  assert.equal(L.overview(next, '2026-10').expense, 10000);
  next = L.saveTransaction(next, transaction({ accountID: uuid(2), amount: '80', installmentMonths: 2 }));
  assert.deepEqual(next.assets[1].repayments.slice(1, 4).map(r => r.amount), ['80.00', '80.00', '0.00']);
  assert.equal(L.deleteTransaction(next, uuid(10)).assets[1].repayments.reduce((sum, r) => sum + L.cents(r.amount), 0), 0);
});
test('还款从最早月份依次抵扣，删除还款恢复计划与付款余额', () => {
  let next = L.saveTransaction(fixture(), transaction({ accountID: uuid(2), amount: '100', installmentMonths: 2 }));
  next = L.saveTransaction(next, transaction({ id: uuid(12), accountID: uuid(2), amount: '150', categoryPresetKey: 'expense_repayment', paymentAccountID: uuid(1) }));
  assert.equal(L.balances(next)[0], 85000);
  assert.deepEqual(next.assets[1].repayments.slice(1, 3).map(r => r.amount), ['0.00', '50.00']);
  next = L.deleteTransaction(next, uuid(12));
  assert.equal(L.balances(next)[0], 100000);
  assert.deepEqual(next.assets[1].repayments.slice(1, 3).map(r => r.amount), ['100.00', '100.00']);
});
test('负债账户普通支出加入本月待还，收入不会增加负债', () => {
  const next = L.saveTransaction(fixture(), transaction({ accountID: uuid(2) }));
  assert.equal(next.assets[1].repayments[0].amount, '25.10');
  assert.equal(L.balances(next)[1], 2510);
});
test('基金买入与赎回同时更新市值、成本、现金，删除可逆', () => {
  let next = L.saveTransaction(fixture(), transaction({ accountID: uuid(3), amount: '100',
    categoryPresetKey: 'expense_fund_purchase', paymentAccountID: uuid(1) }));
  assert.deepEqual(L.balances(next), [90000, 0, 30000]);
  assert.equal(next.assets[2].fundCost, '300.00');
  next = L.saveTransaction(next, transaction({ id: uuid(11), kind: 'income', accountID: uuid(1),
    amount: '50', categoryPresetKey: 'income_fund_redemption', paymentAccountID: uuid(3) }));
  assert.deepEqual(L.balances(next), [95000, 0, 25000]);
  next = L.deleteTransaction(L.deleteTransaction(next, uuid(10)), uuid(11));
  assert.deepEqual(L.balances(next), [100000, 0, 20000]);
});
test('禁止不匹配分类、非法账户、零金额、同账户还款和错误分期', () => {
  for (const overrides of [{ amount: '0' }, { accountID: 'missing' }, { categoryPresetKey: 'income_salary' },
    { installmentMonths: 2 }, { accountID: uuid(2), installmentMonths: 25 },
    { accountID: uuid(2), categoryPresetKey: 'expense_repayment', paymentAccountID: uuid(2) },
    { accountID: uuid(1), categoryPresetKey: 'expense_fund_purchase', paymentAccountID: uuid(3) }]) {
    assert.throws(() => L.saveTransaction(fixture(), transaction(overrides)));
  }
});
test('完整 version 2 导入导出保持账户、分期与账目，不重复应用流水', () => {
  const initial = L.saveTransaction(fixture(), transaction({ accountID: uuid(2), installmentMonths: 3 }));
  const next = L.parseBackup(L.exportBackup(initial));
  assert.deepEqual(L.balances(next), L.balances(initial));
  assert.deepEqual(next.assets, initial.assets);
  assert.deepEqual(next.transactions, JSON.parse(JSON.stringify(initial.transactions)));
});
test('生成的分类和还款计划 ID 可以被 Swift UUID 解析', () => {
  const pattern = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
  const ledger = fixture();
  for (const record of [...ledger.categories, ...ledger.assets, ...ledger.assets.flatMap(a => a.repayments)]) assert.match(record.id, pattern);
});
test('所有原版账户类型、基金活动与可选字段可以往返', () => {
  const initial = fixture();
  initial.assets = L.ASSET_KINDS.map((kind, i) => L.newAsset(uuid(i + 100), kind, kind, '0.00'));
  const fund = initial.assets.find(a => a.kind === 'fund');
  fund.fundActivities.push({ id: uuid(900), kind: 'valuation', amount: '-10.00', occurredAt: '2026-10-30T00:00:00Z', note: '测试数据' });
  assert.deepEqual(L.parseBackup(L.exportBackup(initial)).assets, initial.assets);
});
test('导入拒绝未知版本、重复记录、悬空引用和坏金额，原账本不变', () => {
  const initial = fixture(); const before = JSON.stringify(initial);
  const invalid = [null, [], { version: 99 }, { ...initial, assets: [initial.assets[0], initial.assets[0]] },
    { ...initial, transactions: [transaction({ accountID: 'missing' })] },
    { ...initial, transactions: [transaction({ amount: '0.001' })] }];
  for (const value of invalid) assert.throws(() => L.parseBackup(JSON.stringify(value)));
  assert.equal(JSON.stringify(initial), before);
});
test('旧备份无 accountID 时只接受唯一账户名称匹配', () => {
  const initial = fixture(); initial.transactions.push(transaction()); delete initial.transactions[0].accountID;
  assert.equal(L.parseBackup(JSON.stringify(initial)).transactions[0].accountID, uuid(1));
  initial.assets.push(L.newAsset(uuid(99), '现金', 'cash', '0'));
  assert.throws(() => L.parseBackup(JSON.stringify(initial)), /无法唯一匹配/);
});
test('OCR 优先实付，不采用余额、优惠或订单号', () => {
  const candidates = L.amountCandidates('订单号 20261030123456\n原价 ¥59.00\n优惠 ¥10.00\n实付 ¥49.00\n余额 ¥1000.00');
  assert.equal(candidates[0].amount, '49.00'); assert.equal(candidates[0].kind, 'expense');
  assert.equal(L.amountCandidates('退款成功\n退款金额 ¥29.90')[0].kind, 'income');
});
test('OCR 草稿不写入正式账目，低置信度文字不自动记账', () => {
  const ledger = fixture(); const before = JSON.stringify(ledger);
  assert.deepEqual(L.amountCandidates('订单号 123456789\n2026-10-30 12:34\n手机号 13812345678'), []);
  L.amountCandidates('实付 ¥12.34'); assert.equal(JSON.stringify(ledger), before);
});
test('月度统计按设备本地月份分组', () => {
  const next = L.saveTransaction(fixture(), transaction());
  assert.equal(L.overview(next, '2026-09').expense, 0);
  assert.equal(L.categoryTotals(next, L.localMonth(transaction().occurredAt))[0].cents, 2510);
});

const transferFixture = () => {
  const ledger = fixture();
  ledger.assets.push(L.newAsset(uuid(4), '余额账户', 'alipay', '200.00'));
  return ledger;
};
const transfer = (overrides = {}) => transaction({ kind: 'transfer', categoryPresetKey: 'expense_transfer',
  accountID: uuid(4), paymentAccountID: uuid(1), amount: '100.00', ...overrides });

test('苹果备份转账方向：paymentAccountID 转出，accountID 转入，总资产和收支不变', () => {
  const original = transferFixture();
  const next = L.saveTransaction(original, transfer());
  assert.deepEqual(L.balances(next), [90000, 0, 20000, 30000]);
  assert.equal(L.balances(next).reduce((sum, value) => sum + value, 0), L.balances(original).reduce((sum, value) => sum + value, 0));
  assert.deepEqual(L.overview(next, '2026-10'), { income: 0, expense: 0, net: 0 });
  assert.deepEqual(L.categoryTotals(next, '2026-10'), []);
  const imported = L.parseBackup(L.exportBackup(next));
  assert.equal(imported.transactions[0].kind, 'transfer');
  assert.equal(imported.transactions[0].paymentAccountID, uuid(1));
  assert.deepEqual(L.balances(imported), L.balances(next));
});
test('转账修改、删除和更改账户后可还原两边余额', () => {
  let next = L.saveTransaction(transferFixture(), transfer());
  next = L.saveTransaction(next, transfer({ amount: '75.00' }));
  assert.deepEqual(L.balances(next), [92500, 0, 20000, 27500]);
  next = L.saveTransaction(next, transfer({ amount: '50.00', accountID: uuid(1), paymentAccountID: uuid(4) }));
  assert.deepEqual(L.balances(next), [105000, 0, 20000, 15000]);
  next = L.deleteTransaction(next, uuid(10));
  assert.deepEqual(L.balances(next), L.balances(transferFixture()));
});
test('转账拒绝缺失账户、同账户、基金或负债账户，以及不匹配分类', () => {
  for (const overrides of [{ paymentAccountID: undefined }, { paymentAccountID: uuid(4) },
    { paymentAccountID: uuid(3) }, { paymentAccountID: uuid(2) }, { accountID: uuid(2) },
    { accountID: uuid(3) }, { categoryPresetKey: 'expense_food' }, { kind: 'expense' }]) {
    assert.throws(() => L.saveTransaction(transferFixture(), transfer(overrides)));
    const malformed = transferFixture(); malformed.transactions.push(transfer(overrides));
    assert.throws(() => L.parseBackup(JSON.stringify(malformed)));
  }
});
test('最新苹果端统计口径：还款、基金买卖、转账、余额调整不算日常收支', () => {
  let next = transferFixture();
  const entries = [transaction({ id: uuid(20), amount: '10.00' }),
    transaction({ id: uuid(21), kind: 'income', amount: '20.00', categoryPresetKey: 'income_salary' }),
    transfer({ id: uuid(22) }),
    transaction({ id: uuid(23), amount: '30.00', accountID: uuid(2), paymentAccountID: uuid(1), categoryPresetKey: 'expense_repayment' }),
    transaction({ id: uuid(24), amount: '40.00', accountID: uuid(3), paymentAccountID: uuid(1), categoryPresetKey: 'expense_fund_purchase' }),
    transaction({ id: uuid(25), amount: '15.00', kind: 'income', accountID: uuid(1), paymentAccountID: uuid(3), categoryPresetKey: 'income_fund_redemption' }),
    transaction({ id: uuid(26), amount: '25.00', kind: 'income', categoryPresetKey: 'income_transfer_in' })];
  for (const entry of entries) next = L.saveTransaction(next, entry);
  assert.deepEqual(L.overview(next, '2026-10'), { income: 2000, expense: 1000, net: 1000 });
  assert.deepEqual(L.categoryTotals(next, '2026-10'), [{ name: '餐饮', cents: 1000 }]);
});

const privateBackupPath = path.resolve(import.meta.dirname, '../tallyexp.json');
test('本机私有苹果备份完整导入并往返，保留所有账目及转账，不改写原文件',
  { skip: !fs.existsSync(privateBackupPath) }, () => {
    const raw = fs.readFileSync(privateBackupPath, 'utf8');
    const original = JSON.parse(raw);
    const imported = L.parseBackup(raw);
    assert.equal(imported.transactions.length, original.transactions.length);
    assert.equal(imported.assets.length, original.assets.length);
    assert.equal(imported.categories.length, original.categories.length);
    assert.equal(imported.transactions.filter(t => t.kind === 'transfer').length, original.transactions.filter(t => t.kind === 'transfer').length);
    const expected = original.transactions.slice().sort((a, b) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt));
    // Use boolean comparisons to avoid printing personal records on assertion failures.
    assert.ok(JSON.stringify(imported.transactions) === JSON.stringify(expected), '原始账目必须完整保留');
    const roundTrip = L.parseBackup(L.exportBackup(imported));
    assert.ok(JSON.stringify(roundTrip.assets) === JSON.stringify(imported.assets), '账户快照不能被重复应用流水');
    assert.ok(JSON.stringify(roundTrip.transactions) === JSON.stringify(imported.transactions), '往返不能改变账目');
    assert.ok(JSON.stringify(L.balances(roundTrip)) === JSON.stringify(L.balances(imported)), '往返后余额必须一致');
    assert.ok(fs.readFileSync(privateBackupPath, 'utf8') === raw, '原始备份文件保持不变');
  });

test('基金实时资产按苹果 fundCurrentValue 取市值，不误用余额或重复叠加流水', () => {
  const ledger = fixture();
  ledger.assets[2].balance = '200.00';
  ledger.assets[2].fundMarketValue = '213.27';
  ledger.transactions.push(transaction({ accountID: uuid(3), kind: 'income', categoryPresetKey: 'income_investment', amount: '8.88' }));
  assert.equal(L.assetValues(ledger)[2], 21327);
  assert.equal(L.assetValues(ledger)[0], 100000);
});
test('基金盈利、亏损和投入与 Swift addFundActivity 相同，不计入日常收支', () => {
  const original = fixture();
  const activity = (amount, kind = 'valuation') => ({ id: uuid(40), kind, amount, occurredAt: '2026-10-30T12:00:00+08:00', note: ' test ' });
  let next = L.addFundActivity(original, uuid(3), activity('12.34'));
  next = L.addFundActivity(next, uuid(3), { ...activity('-2.15'), id: uuid(41) });
  assert.equal(next.assets[2].fundMarketValue, '210.19');
  assert.equal(next.assets[2].fundCost, '200.00');
  assert.equal(next.assets[2].balance, '210.19');
  assert.equal(next.assets[2].fundActivities[0].note, 'test');
  assert.equal(next.transactions.length, 0);
  assert.deepEqual(L.overview(next, '2026-10'), { income: 0, expense: 0, net: 0 });
  next = L.addFundActivity(next, uuid(3), { ...activity('50', 'investment'), id: uuid(42) });
  assert.equal(next.assets[2].fundCost, '250.00');
  assert.equal(next.assets[2].fundMarketValue, '210.19', 'Apple 投入只更新成本，非零市值不变');
  assert.equal(original.assets[2].fundMarketValue, '200.00');
  assert.throws(() => L.addFundActivity(original, uuid(1), activity('1')));
  assert.equal(L.parseBackup(L.exportBackup(next)).assets[2].fundMarketValue, '210.19');
});
test('零市值基金投入初始化市值，买入赎回和撤销保留原有盈亏', () => {
  let ledger = fixture(); ledger.assets[2] = L.newAsset(uuid(3), '基金', 'fund', '0');
  ledger = L.addFundActivity(ledger, uuid(3), { id: uuid(40), kind: 'investment', amount: '100', note: '', occurredAt: new Date().toISOString() });
  assert.equal(ledger.assets[2].fundMarketValue, '100.00');
  ledger = L.addFundActivity(ledger, uuid(3), { id: uuid(41), kind: 'valuation', amount: '-3.27', note: '', occurredAt: new Date().toISOString() });
  ledger = L.saveTransaction(ledger, transaction({ accountID: uuid(3), paymentAccountID: uuid(1), categoryPresetKey: 'expense_fund_purchase', amount: '20' }));
  assert.equal(L.assetValues(ledger)[2], 11673);
  assert.equal(ledger.assets[2].fundCost, '120.00');
  ledger = L.deleteTransaction(ledger, uuid(10));
  assert.equal(L.assetValues(ledger)[2], 9673);
});
test('花呗计划无论导入顺序如何都按月份正序，默认只返回下月', () => {
  const asset = L.newAsset(uuid(1), '花呗', 'alipayCredit', '0');
  asset.repayments.reverse();
  assert.deepEqual(L.repaymentRows(asset, false).map(r => r.monthOffset), [1]);
  assert.deepEqual(L.repaymentRows(asset, true).map(r => r.monthOffset), Array.from({ length: 25 }, (_, i) => i));
  assert.equal(asset.repayments[0].monthOffset, 24, '展示不可改写原计划');
});
test('总览两张分类图与近七天收支排除转账和基金买卖', () => {
  const ledger = fixture();
  ledger.transactions = [transaction(), transaction({ id: uuid(11), kind: 'income', categoryPresetKey: 'income_salary', amount: '100' }), transaction({ id: uuid(12), categoryPresetKey: 'expense_fund_purchase', amount: '80' })];
  assert.deepEqual(L.categoryTotals(ledger, '2026-10', 'income'), [{ name: '工资', cents: 10000 }]);
  assert.deepEqual(L.categoryTotals(ledger, '2026-10'), [{ name: '餐饮', cents: 2510 }]);
  const flows = L.dailyFlows(ledger, '2026-10', new Date('2026-10-30T20:00:00+08:00'));
  assert.equal(flows.length, 7);
  assert.equal(flows.reduce((s, d) => s + d.income, 0), 10000);
  assert.equal(flows.reduce((s, d) => s + d.expense, 0), 2510);
});
test('私有苹果备份的基金展示逐一对齐 fundMarketValue，而非 balanceMap', { skip: !fs.existsSync(path.resolve('tallyexp.json')) }, () => {
  const raw = JSON.parse(fs.readFileSync('tallyexp.json', 'utf8'));
  const ledger = L.parseBackup(JSON.stringify(raw));
  assert.ok(raw.assets.every((a, i) => a.kind !== 'fund' || L.assetValues(ledger)[i] === L.cents(a.fundMarketValue ?? a.balance)), '基金展示必须采用苹果市值');
});
