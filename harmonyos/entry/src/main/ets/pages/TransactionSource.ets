import { TransactionRowSnapshot } from '../core/Ledger';

export class TransactionSource implements IDataSource {
  private items: TransactionRowSnapshot[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): TransactionRowSnapshot { return this.items[index]; }
  replace(items: TransactionRowSnapshot[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) this.listeners.push(listener);
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener) => item !== listener);
  }
}
