/* SPDX-License-Identifier: GPL-3.0-only
 * gallery-gtk2 OUT.json: the Qt gallery's controls (rig/m9/gallery.py) in GTK 2, in one window at the screen's top
 * left; once drawn it writes where the File menu and the OK button are, and the theme GTK loaded, to OUT.json, so a
 * driver can open the menu and point at the button with real input (see gallery_gtk3.py).
 * Build: cc -o gallery-gtk2 gallery-gtk2.c $(pkg-config --cflags --libs gtk+-2.0) */
#include <gtk/gtk.h>
#include <stdio.h>

static GtkWidget *window, *file_item, *ok_button, *hbar, *vbar;
static const char *out_path;

static GtkWidget *framed(const char *title, GtkWidget *child)
{
	GtkWidget *f = gtk_frame_new(title);
	gtk_container_set_border_width(GTK_CONTAINER(child), 6);
	gtk_container_add(GTK_CONTAINER(f), child);
	return f;
}

static void centre(GtkWidget *w, int *x, int *y)
{
	int wx = 0, wy = 0;
	gtk_widget_translate_coordinates(w, window, 0, 0, &wx, &wy);
	*x = wx + w->allocation.width / 2;
	*y = wy + w->allocation.height / 2;
}

static gboolean report(gpointer data)
{
	int fx, fy, ox, oy;
	gchar *theme = NULL;
	FILE *f;
	(void)data;
	centre(file_item, &fx, &fy);
	centre(ok_button, &ox, &oy);
	g_object_get(gtk_settings_get_default(), "gtk-theme-name", &theme, NULL);
	f = fopen(out_path, "w");
	if (!f)
		return FALSE;
	{
		int hx = 0, hy = 0, vx = 0, vy = 0;
		gtk_widget_translate_coordinates(hbar, window, 0, 0, &hx, &hy);
		gtk_widget_translate_coordinates(vbar, window, 0, 0, &vx, &vy);
		fprintf(f, "{\"file\": [%d, %d], \"ok\": [%d, %d], \"bars\": {\"h\": [%d, %d, %d, %d], \"v\": [%d, %d, %d, %d]}, "
			"\"theme\": \"%s\", \"gtk\": \"%d.%d.%d\", \"size\": [%d, %d]}\n",
			fx, fy, ox, oy, hx, hy, hbar->allocation.width, hbar->allocation.height, vx, vy, vbar->allocation.width,
			vbar->allocation.height, theme ? theme : "", gtk_major_version, gtk_minor_version, gtk_micro_version,
			window->allocation.width, window->allocation.height);
	}
	fclose(f);
	g_free(theme);
	return FALSE;
}

static GtkWidget *menu_item(GtkWidget *menu, const char *label)
{
	GtkWidget *item = gtk_menu_item_new_with_label(label);
	gtk_menu_shell_append(GTK_MENU_SHELL(menu), item);
	return item;
}

int main(int argc, char **argv)
{
	GtkWidget *outer, *bar, *table, *box, *row, *w, *r1, *combo, *nb, *sw, *tree;
	GtkTreeStore *store;
	GtkListStore *list;
	GtkTreeIter it, child;
	const char *titles[] = { "File", "Edit", "View", "Special" };
	const char *folders[] = { "System Folder", "Documents" };
	const char *tabs[] = { "General", "Fonts", "Desktop" };
	int i, j;

	gtk_init(&argc, &argv);
	out_path = argc > 1 ? argv[1] : "/dev/null";
	window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
	gtk_window_set_title(GTK_WINDOW(window), "Kubabbar Glass 9 gallery, GTK 2");
	gtk_window_set_default_size(GTK_WINDOW(window), 860, 600);
	g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), NULL);
	outer = gtk_vbox_new(FALSE, 6);
	gtk_container_add(GTK_CONTAINER(window), outer);

	bar = gtk_menu_bar_new();
	for (i = 0; i < 4; i++) {
		GtkWidget *item = gtk_menu_item_new_with_label(titles[i]);
		GtkWidget *menu = gtk_menu_new();
		if (i == 0) {
			GtkWidget *recent, *sub;
			menu_item(menu, "Open");
			menu_item(menu, "Close");
			gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
			recent = menu_item(menu, "Recent");
			sub = gtk_menu_new();
			menu_item(sub, "One");
			gtk_menu_item_set_submenu(GTK_MENU_ITEM(recent), sub);
			file_item = item;
		} else {
			menu_item(menu, "Item");
		}
		gtk_menu_item_set_submenu(GTK_MENU_ITEM(item), menu);
		gtk_menu_shell_append(GTK_MENU_SHELL(bar), item);
	}
	gtk_box_pack_start(GTK_BOX(outer), bar, FALSE, FALSE, 0);
	table = gtk_table_new(3, 3, FALSE);
	gtk_table_set_row_spacings(GTK_TABLE(table), 8);
	gtk_table_set_col_spacings(GTK_TABLE(table), 8);
	gtk_container_set_border_width(GTK_CONTAINER(table), 8);
	gtk_box_pack_start(GTK_BOX(outer), table, TRUE, TRUE, 0);

	box = gtk_vbox_new(FALSE, 4);
	ok_button = gtk_button_new_with_label("OK");
	GTK_WIDGET_SET_FLAGS(ok_button, GTK_CAN_DEFAULT);
	gtk_widget_set_tooltip_text(ok_button, "A tooltip, the help tag");
	gtk_box_pack_start(GTK_BOX(box), ok_button, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), gtk_button_new_with_label("Cancel"), FALSE, FALSE, 0);
	w = gtk_button_new_with_label("Pressed");
	gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	g_object_set_data(G_OBJECT(window), "pressed", w);
	w = gtk_button_new_with_label("Disabled");
	gtk_widget_set_sensitive(w, FALSE);
	gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	row = gtk_toolbar_new();
	gtk_toolbar_set_style(GTK_TOOLBAR(row), GTK_TOOLBAR_TEXT);
	for (i = 0; i < 3; i++) {
		GtkToolItem *t = gtk_toggle_tool_button_new();
		gtk_tool_button_set_label(GTK_TOOL_BUTTON(t), (const char *[]){ "Bevel", "Tool", "On" }[i]);
		gtk_toggle_tool_button_set_active(GTK_TOGGLE_TOOL_BUTTON(t), i == 2);
		gtk_toolbar_insert(GTK_TOOLBAR(row), t, -1);
	}
	gtk_box_pack_start(GTK_BOX(box), row, FALSE, FALSE, 0);
	gtk_table_attach_defaults(GTK_TABLE(table), framed("Buttons", box), 0, 1, 0, 1);

	box = gtk_vbox_new(FALSE, 2);
	for (i = 0; i < 3; i++) {
		w = gtk_check_button_new_with_label((const char *[]){ "Checked", "Unchecked", "Mixed" }[i]);
		gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(w), i == 0);
		gtk_toggle_button_set_inconsistent(GTK_TOGGLE_BUTTON(w), i == 2);
		gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	}
	r1 = gtk_radio_button_new_with_label(NULL, "Radio on");
	gtk_box_pack_start(GTK_BOX(box), r1, FALSE, FALSE, 0);
	gtk_box_pack_start(GTK_BOX(box), gtk_radio_button_new_with_label_from_widget(GTK_RADIO_BUTTON(r1), "Radio off"), FALSE, FALSE, 0);
	gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(r1), TRUE);
	w = gtk_check_button_new_with_label("Disabled");
	gtk_widget_set_sensitive(w, FALSE);
	gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	gtk_table_attach_defaults(GTK_TABLE(table), framed("Choices", box), 1, 2, 0, 1);

	box = gtk_vbox_new(FALSE, 4);
	combo = gtk_combo_box_new_text();
	gtk_combo_box_append_text(GTK_COMBO_BOX(combo), "Pop-up menu");
	gtk_combo_box_append_text(GTK_COMBO_BOX(combo), "Second");
	gtk_combo_box_set_active(GTK_COMBO_BOX(combo), 0);
	gtk_box_pack_start(GTK_BOX(box), combo, FALSE, FALSE, 0);
	combo = gtk_combo_box_entry_new_text();
	gtk_combo_box_append_text(GTK_COMBO_BOX(combo), "Combo box");
	gtk_combo_box_set_active(GTK_COMBO_BOX(combo), 0);
	gtk_box_pack_start(GTK_BOX(box), combo, FALSE, FALSE, 0);
	w = gtk_entry_new();
	gtk_entry_set_text(GTK_ENTRY(w), "Text field");
	gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	w = gtk_spin_button_new_with_range(0, 99, 1);
	gtk_spin_button_set_value(GTK_SPIN_BUTTON(w), 9);
	gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	gtk_table_attach_defaults(GTK_TABLE(table), framed("Fields", box), 2, 3, 0, 1);

	box = gtk_vbox_new(FALSE, 6);
	w = gtk_hscale_new_with_range(0, 100, 1);
	gtk_scale_set_draw_value(GTK_SCALE(w), FALSE);
	gtk_range_set_value(GTK_RANGE(w), 40);
	gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	w = gtk_progress_bar_new();
	gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(w), 0.62);
	gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	w = gtk_progress_bar_new();
	gtk_progress_bar_pulse(GTK_PROGRESS_BAR(w));
	gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	hbar = w = gtk_hscrollbar_new(GTK_ADJUSTMENT(gtk_adjustment_new(20, 0, 100, 1, 30, 30)));
	gtk_box_pack_start(GTK_BOX(box), w, FALSE, FALSE, 0);
	gtk_table_attach_defaults(GTK_TABLE(table), framed("Ranges", box), 0, 1, 1, 2);

	nb = gtk_notebook_new();
	for (i = 0; i < 3; i++) {
		gchar *text = g_strdup_printf("%s page", tabs[i]);
		w = gtk_label_new(text);
		gtk_widget_set_size_request(w, 220, 90);
		gtk_notebook_append_page(GTK_NOTEBOOK(nb), w, gtk_label_new(tabs[i]));
		g_free(text);
	}
	gtk_table_attach_defaults(GTK_TABLE(table), nb, 1, 2, 1, 2);
	vbar = w = gtk_vscrollbar_new(GTK_ADJUSTMENT(gtk_adjustment_new(30, 0, 100, 1, 25, 25)));
	gtk_widget_set_size_request(w, -1, 150);
	gtk_table_attach(GTK_TABLE(table), w, 2, 3, 1, 2, GTK_SHRINK, GTK_FILL, 0, 0);

	store = gtk_tree_store_new(3, G_TYPE_STRING, G_TYPE_STRING, G_TYPE_STRING);
	for (i = 0; i < 2; i++) {
		gtk_tree_store_append(store, &it, NULL);
		gtk_tree_store_set(store, &it, 0, folders[i], 1, "--", 2, "folder", -1);
		for (j = 0; j < 2; j++) {
			gtk_tree_store_append(store, &child, &it);
			gtk_tree_store_set(store, &child, 0, j ? "Item two" : "Item one", 1, "12 KB", 2, "document", -1);
		}
	}
	tree = gtk_tree_view_new_with_model(GTK_TREE_MODEL(store));
	for (i = 0; i < 3; i++) {
		GtkTreeViewColumn *col = gtk_tree_view_column_new_with_attributes((const char *[]){ "Name", "Size", "Kind" }[i],
			gtk_cell_renderer_text_new(), "text", i, NULL);
		gtk_tree_view_column_set_clickable(col, TRUE);
		gtk_tree_view_append_column(GTK_TREE_VIEW(tree), col);
	}
	{
		GtkTreePath *first = gtk_tree_path_new_first(), *sel = gtk_tree_path_new_from_string("0:0");
		gtk_tree_view_expand_row(GTK_TREE_VIEW(tree), first, FALSE);
		gtk_tree_selection_select_path(gtk_tree_view_get_selection(GTK_TREE_VIEW(tree)), sel);
		gtk_tree_path_free(first);
		gtk_tree_path_free(sel);
	}
	sw = gtk_scrolled_window_new(NULL, NULL);
	gtk_scrolled_window_set_shadow_type(GTK_SCROLLED_WINDOW(sw), GTK_SHADOW_IN);
	gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(sw), GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
	gtk_widget_set_size_request(sw, -1, 150);
	gtk_container_add(GTK_CONTAINER(sw), tree);
	gtk_table_attach_defaults(GTK_TABLE(table), sw, 0, 2, 2, 3);

	list = gtk_list_store_new(2, G_TYPE_STRING, G_TYPE_STRING);
	for (i = 0; i < 3; i++) {
		gtk_list_store_append(list, &it);
		gtk_list_store_set(list, &it, 0, "", 1, "", -1);
	}
	tree = gtk_tree_view_new_with_model(GTK_TREE_MODEL(list));
	for (i = 0; i < 2; i++) {
		GtkTreeViewColumn *col = gtk_tree_view_column_new_with_attributes(i ? "Value" : "Column",
			gtk_cell_renderer_text_new(), "text", i, NULL);
		gtk_tree_view_column_set_clickable(col, TRUE);
		gtk_tree_view_column_set_sort_indicator(col, i == 0);
		gtk_tree_view_append_column(GTK_TREE_VIEW(tree), col);
	}
	sw = gtk_scrolled_window_new(NULL, NULL);
	gtk_scrolled_window_set_shadow_type(GTK_SCROLLED_WINDOW(sw), GTK_SHADOW_IN);
	gtk_container_add(GTK_CONTAINER(sw), tree);
	gtk_table_attach_defaults(GTK_TABLE(table), sw, 2, 3, 2, 3);

	gtk_window_move(GTK_WINDOW(window), 0, 0);
	gtk_widget_show_all(window);
	gtk_widget_grab_default(ok_button);
	/* a button held pressed, as the Qt gallery's setDown(true) */
	gtk_widget_set_state(GTK_WIDGET(g_object_get_data(G_OBJECT(window), "pressed")), GTK_STATE_ACTIVE);
	g_timeout_add(800, report, NULL);
	gtk_main();
	return 0;
}
