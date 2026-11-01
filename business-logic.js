(function exposeCostTrackLogic(root) {
  function createRevenueRecord(data) {
    const adultCustomers = Number(data.adult_customers || 0);
    const childCustomers = Number(data.child_customers || 0);
    const seniorCustomers = Number(data.senior_pwd_customers || 0);
    const adultRate = Number(data.adult_rate || 599);
    const childRate = Number(data.child_rate || 299);
    const seniorRate = Number(data.senior_pwd_rate || Math.round(adultRate * 0.8));
    const counts = [adultCustomers, childCustomers, seniorCustomers];
    const rates = [adultRate, childRate, seniorRate];
    if (counts.some(value => !Number.isInteger(value) || value < 0)) throw new RangeError('Customer counts must be non-negative whole numbers.');
    if (counts.reduce((sum, value) => sum + value, 0) < 1) throw new RangeError('At least one customer is required.');
    if (rates.some(value => !Number.isFinite(value) || value < 0)) throw new RangeError('Revenue rates must be valid non-negative amounts.');
    return {
      status: 'Active',
      ...data,
      adult_customers: adultCustomers,
      adult_rate: adultRate,
      child_customers: childCustomers,
      child_rate: childRate,
      senior_pwd_customers: seniorCustomers,
      senior_pwd_rate: seniorRate,
      adult_revenue: adultCustomers * adultRate,
      child_revenue: childCustomers * childRate,
      senior_pwd_revenue: seniorCustomers * seniorRate,
      total_customers: adultCustomers + childCustomers + seniorCustomers,
      total_revenue: adultCustomers * adultRate + childCustomers * childRate + seniorCustomers * seniorRate
    };
  }

  function computedRecipeCost(recipe, ingredients) {
    const ingredientById = new Map(ingredients.map(item => [item.id, item]));
    const wastage = Number(recipe.wastage || 0);
    if (!Number.isFinite(wastage) || wastage < 0) throw new RangeError('Recipe wastage must be a non-negative number.');
    const baseCost = recipe.ingredients.reduce((sum, line) => {
      const item = ingredientById.get(line.ingredientId);
      const quantity = Number(line.quantity);
      if (!item || !Number.isFinite(quantity) || quantity <= 0) throw new RangeError('Recipe ingredients must reference valid inventory with positive quantities.');
      return sum + Number(item.cost) * quantity;
    }, 0);
    return baseCost * (1 + wastage / 100);
  }

  function reservationRevenue(reservation) {
    const estimated = Number(reservation.estimatedRevenue);
    if (Number.isFinite(estimated) && estimated > 0) return estimated;
    const adults = Number(reservation.adults || reservation.guests || 0);
    const children = Number(reservation.children || 0);
    if (![adults, children].every(value => Number.isInteger(value) && value >= 0)) {
      throw new RangeError('Reservation guest counts must be non-negative whole numbers.');
    }
    return adults * 599 + children * 299;
  }

  const logic = { createRevenueRecord, computedRecipeCost, reservationRevenue };
  root.CostTrackLogic = logic;
  if (typeof module !== 'undefined' && module.exports) module.exports = logic;
})(globalThis);
