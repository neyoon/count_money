import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Ledger, emptyLedger, exportBackup, parseBackup } from '../core/Ledger';

export class LedgerRepository {
  private store: relationalStore.RdbStore | undefined = undefined;

  async open(context: common.Context): Promise<Ledger> {
    this.store = await relationalStore.getRdbStore(context, {
      name: 'count-money.db', securityLevel: relationalStore.SecurityLevel.S1
    });
    await this.store.executeSql('CREATE TABLE IF NOT EXISTS ledger (id INTEGER PRIMARY KEY CHECK(id = 1), payload TEXT NOT NULL)');
    await this.store.executeSql('CREATE TABLE IF NOT EXISTS recovery (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL)');
    const rows = await this.store.querySql('SELECT payload FROM ledger WHERE id = 1');
    try {
      if (rows.goToFirstRow()) return parseBackup(rows.getString(0));
    } finally { rows.close(); }
    const initial = emptyLedger();
    await this.save(initial);
    return initial;
  }

  async save(ledger: Ledger): Promise<void> {
    const store = this.store;
    if (!store) throw new Error('数据库尚未打开');
    const payload = exportBackup(ledger);
    store.beginTransaction();
    try {
      await store.executeSql('INSERT INTO recovery (payload) SELECT payload FROM ledger WHERE id = 1');
      await store.executeSql('INSERT OR REPLACE INTO ledger (id, payload) VALUES (1, ?)', [payload]);
      await store.executeSql('DELETE FROM recovery WHERE id NOT IN (SELECT id FROM recovery ORDER BY id DESC LIMIT 10)');
      store.commit();
    } catch (error) { store.rollBack(); throw new Error((error as Error).message); }
  }

  async previous(): Promise<Ledger> {
    if (!this.store) throw new Error('数据库尚未打开');
    const rows = await this.store.querySql('SELECT payload FROM recovery ORDER BY id DESC LIMIT 1');
    try {
      if (!rows.goToFirstRow()) throw new Error('还没有可恢复的上一个版本');
      return parseBackup(rows.getString(0));
    } finally { rows.close(); }
  }
}
