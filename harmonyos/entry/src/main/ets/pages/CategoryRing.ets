import { CategoryTotal } from '../core/Ledger';

@Component
export struct CategoryRing {
  @Prop @Watch('draw') items: CategoryTotal[] = [];
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private colors: string[] = ['#0969DA', '#1A7F37', '#8250DF', '#BF8700', '#CF222E', '#0891B2', '#DB61A2', '#6E7781'];

  private draw(): void {
    const width = this.context.width;
    const height = this.context.height;
    if (width <= 0 || height <= 0) return;
    this.context.clearRect(0, 0, width, height);
    const total = this.items.reduce((sum: number, item: CategoryTotal) => sum + item.cents, 0);
    if (total <= 0) return;
    const radius = Math.min(width, height) / 2 - 3;
    let angle = -Math.PI / 2;
    this.items.forEach((item: CategoryTotal, index: number) => {
      const end = angle + item.cents / total * Math.PI * 2;
      this.context.beginPath();
      this.context.arc(width / 2, height / 2, radius, angle, end);
      this.context.arc(width / 2, height / 2, radius * 0.58, end, angle, true);
      this.context.closePath();
      this.context.fillStyle = this.colors[index % this.colors.length];
      this.context.fill();
      angle = end;
    });
  }

  build() {
    Canvas(this.context).width(210).height(210)
      .onReady(() => { this.draw(); })
  }
}
