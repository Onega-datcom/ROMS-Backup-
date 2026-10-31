const SUPABASE_URL = 'https://niiodqunoflblfcgdods.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_IVE25Rqzu-lDLFayVYmhfQ_dvPIO6E5';

window.supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY
);

window.supabaseRecord = {
  async load(collection) {
    const { data, error } = await window.supabaseClient
      .from('app_records')
      .select('record_id, data')
      .eq('collection', collection);
    if (error) throw error;
    return data || [];
  },
  async save(collection, records) {
    const rows = records.map(record => ({
      collection,
      record_id: String(record.id),
      data: record,
      updated_at: new Date().toISOString()
    }));
    const { error } = await window.supabaseClient
      .from('app_records')
      .upsert(rows, { onConflict: 'collection,record_id' });
    if (error) throw error;
  },
  async replace(collection, records) {
    const { error: deleteError } = await window.supabaseClient
      .from('app_records')
      .delete()
      .eq('collection', collection);
    if (deleteError) throw deleteError;
    if (records.length) await this.save(collection, records);
  }
};
