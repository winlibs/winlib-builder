#ifndef WINLIB_PANGO_GLIB_COMPAT_H
#define WINLIB_PANGO_GLIB_COMPAT_H

#include <glib.h>
#include <string.h>

#if !GLIB_CHECK_VERSION(2, 80, 0)
#ifndef G_GNUC_FALLTHROUGH
#define G_GNUC_FALLTHROUGH ((void) 0)
#endif

#define G_UNICODE_BREAK_AKSARA \
    ((GUnicodeBreakType) (G_UNICODE_BREAK_ZERO_WIDTH_JOINER + 1))
#define G_UNICODE_BREAK_AKSARA_PRE_BASE \
    ((GUnicodeBreakType) (G_UNICODE_BREAK_ZERO_WIDTH_JOINER + 2))
#define G_UNICODE_BREAK_AKSARA_START \
    ((GUnicodeBreakType) (G_UNICODE_BREAK_ZERO_WIDTH_JOINER + 3))
#define G_UNICODE_BREAK_VIRAMA_FINAL \
    ((GUnicodeBreakType) (G_UNICODE_BREAK_ZERO_WIDTH_JOINER + 4))
#define G_UNICODE_BREAK_VIRAMA \
    ((GUnicodeBreakType) (G_UNICODE_BREAK_ZERO_WIDTH_JOINER + 5))

#define g_memdup2(mem, byte_size) g_memdup((mem), (guint) (byte_size))

G_INLINE_FUNC GPtrArray *
winlib_g_ptr_array_copy (GPtrArray *array,
                         GCopyFunc  func,
                         gpointer   user_data)
{
  GPtrArray *copy;
  guint i;

  copy = g_ptr_array_sized_new (array->len);
  for (i = 0; i < array->len; i++)
    g_ptr_array_add (copy,
                     func ? func (array->pdata[i], user_data) : array->pdata[i]);

  return copy;
}

G_INLINE_FUNC GPtrArray *
winlib_g_hash_table_get_values_as_ptr_array (GHashTable *hash_table)
{
  GPtrArray *array;
  GList *values;
  GList *item;

  array = g_ptr_array_sized_new (g_hash_table_size (hash_table) + 1);
  values = g_hash_table_get_values (hash_table);
  for (item = values; item; item = item->next)
    g_ptr_array_add (array, item->data);
  g_list_free (values);

  return array;
}

G_INLINE_FUNC gpointer *
winlib_g_ptr_array_steal (GPtrArray *array,
                          gsize     *len)
{
  gpointer *data;

  data = g_new (gpointer, array->len + 1);
  if (array->len)
    memcpy (data, array->pdata, array->len * sizeof (gpointer));
  data[array->len] = NULL;
  if (len)
    *len = array->len;
  g_ptr_array_set_size (array, 0);

  return data;
}

#define g_ptr_array_copy winlib_g_ptr_array_copy
#define g_hash_table_get_values_as_ptr_array \
    winlib_g_hash_table_get_values_as_ptr_array
#define g_ptr_array_steal winlib_g_ptr_array_steal
#endif

#endif
