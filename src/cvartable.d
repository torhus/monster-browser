module cvartable;

import std.algorithm : canFind;

import org.eclipse.swt.SWT;
import org.eclipse.swt.events.MenuDetectEvent;
import org.eclipse.swt.events.MenuDetectListener;
import org.eclipse.swt.program.Program;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Menu;
import org.eclipse.swt.widgets.MenuItem;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.widgets.Table;
import org.eclipse.swt.widgets.TableColumn;
import org.eclipse.swt.widgets.TableItem;

import common;
import settings;


__gshared CvarTable cvarTable;  ///


///
class CvarTable
{
	///
	this(Composite parent)
	{
		parent_ = parent;
		table_ = new Table(parent_, SWT.BORDER | SWT.FULL_SELECTION);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		TableColumn column = new TableColumn(table_, SWT.HIDE_SELECTION);
		column.setText("Key");
		column = new TableColumn(table_, SWT.NONE);
		column.setText("Value");

		int[] widths = parseIntList(getSessionState("cvarColumnWidths"), 2, 90);

		// add columns
		table_.getColumn(0).setWidth(widths[0]);
		table_.getColumn(1).setWidth(widths[1]);

		table_.addSelectionListener(new class SelectionAdapter {
			override void widgetDefaultSelected(SelectionEvent e)
			{
				auto item = cast(TableItem)e.item;
				maybeOpenUrl(item.getText(1));
			}
		});

		table_.setMenu(createContextMenu());
		table_.addMenuDetectListener(new class MenuDetectListener {
			void menuDetected(MenuDetectEvent e)
			{
				if (table_.getSelectionCount() == 0)
					e.doit = false;
			}
		});
	}

	Table getTable() { return table_; }  ///

	void setItems(string[][] items)  ///
	{
		table_.setRedraw(false);
		table_.setItemCount(0);
		foreach (v; items) {
			TableItem item = new TableItem(table_, SWT.NONE);
      		item.setText(v);
      	}
		table_.setRedraw(true);
  	}

	void clear()  ///
	{
		table_.removeAll();
	}

	/************************************************
	            PRIVATE STUFF
	 ************************************************/
private:
	Table table_;
	Composite parent_;


	Menu createContextMenu()
	{
		Menu menu = new Menu(table_);

		MenuItem item = new MenuItem(menu, SWT.PUSH);
		item.setText("Open link\tEnter");
		menu.setDefaultItem(item);
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e) {
				string s = table_.getItem(table_.getSelectionIndex()).getText(1);
				maybeOpenUrl(s);
			}
		});

		item = new MenuItem(menu, SWT.PUSH);
		item.setText("Copy value\tCtrl+C");
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e) {
				string s = table_.getItem(table_.getSelectionIndex()).getText(1);
				copyToClipboard(s);
			}
		});


		return menu;
	}


	void maybeOpenUrl(string maybeUrl)
	{
		if (maybeUrl.canFind('.') && !maybeUrl.canFind(' '))
			Program.launch(maybeUrl);
	}
}
