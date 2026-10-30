export class CategoryStyle {
  static icon(key: string): Resource {
    switch (key) {
      case 'expense_transfer': return $r('app.media.category_transfer');
      case 'expense_food': return $r('app.media.category_food');
      case 'expense_transport': return $r('app.media.category_transport');
      case 'expense_repayment': return $r('app.media.category_repayment');
      case 'expense_fund_purchase': return $r('app.media.category_fund');
      case 'expense_daily': return $r('app.media.category_daily');
      case 'expense_shopping': return $r('app.media.category_shopping');
      case 'expense_subscription': return $r('app.media.category_subscription');
      case 'expense_entertainment': return $r('app.media.category_entertainment');
      case 'expense_health': return $r('app.media.category_health');
      case 'expense_education': return $r('app.media.category_education');
      case 'expense_family': return $r('app.media.category_family');
      case 'expense_other': return $r('app.media.category_other');
      case 'income_salary': return $r('app.media.category_salary');
      case 'income_bonus': return $r('app.media.category_bonus');
      case 'income_freelance': return $r('app.media.category_freelance');
      case 'income_investment': return $r('app.media.category_fund');
      case 'income_fund_redemption': return $r('app.media.category_fund');
      case 'income_interest': return $r('app.media.category_interest');
      case 'income_reimbursement': return $r('app.media.category_reimbursement');
      case 'income_refund': return $r('app.media.category_refund');
      case 'income_transfer_in': return $r('app.media.category_refund');
      case 'income_gift': return $r('app.media.category_gift');
      case 'income_sale': return $r('app.media.category_sale');
      case 'income_other': return $r('app.media.category_other');
      default: return $r('app.media.category_custom');
    }
  }
}
