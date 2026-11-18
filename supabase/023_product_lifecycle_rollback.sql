begin;

drop trigger if exists costtrack_physical_counts_require_active_product
  on public.physical_counts;
drop trigger if exists costtrack_waste_logs_require_active_product
  on public.waste_logs;
drop trigger if exists a_costtrack_waste_logs_require_active_product
  on public.waste_logs;
drop trigger if exists costtrack_inventory_transactions_require_active_product
  on public.inventory_transactions;
drop trigger if exists costtrack_dish_recipe_ingredients_require_active_product
  on public.dish_recipe_ingredients;
drop trigger if exists costtrack_recipe_ingredients_require_active_product
  on public.recipe_ingredients;

drop function if exists public.costtrack_require_active_product();
drop function if exists public.costtrack_product_lifecycle(text, text, text);

commit;
