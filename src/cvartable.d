module cvartable;

import std.algorithm : canFind;
import std.regex;

import org.eclipse.swt.SWT;
import org.eclipse.swt.events.KeyAdapter;
import org.eclipse.swt.events.KeyEvent;
import org.eclipse.swt.events.MenuDetectEvent;
import org.eclipse.swt.events.MenuDetectListener;
import org.eclipse.swt.graphics.TextLayout;
import org.eclipse.swt.graphics.TextStyle;
import org.eclipse.swt.program.Program;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Display;
import org.eclipse.swt.widgets.Event;
import org.eclipse.swt.widgets.Listener;
import org.eclipse.swt.widgets.Menu;
import org.eclipse.swt.widgets.MenuItem;
import org.eclipse.swt.events.SelectionAdapter;
import org.eclipse.swt.events.SelectionEvent;
import org.eclipse.swt.widgets.Table;
import org.eclipse.swt.widgets.TableColumn;
import org.eclipse.swt.widgets.TableItem;

import common;
import serverdata;
import settings;


__gshared CvarTable cvarTable;  ///

// should correspond to serverlist.CvarColumn
immutable cvarHeaders = ["Key", "Value"];

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
		column.setText(cvarHeaders[CvarColumn.KEY]);
		column = new TableColumn(table_, SWT.NONE);
		column.setText(cvarHeaders[CvarColumn.VALUE]);

		int[] widths = parseIntList(getSessionState("cvarColumnWidths"), 2, 90);

		// add columns
		table_.getColumn(0).setWidth(widths[0]);
		table_.getColumn(1).setWidth(widths[1]);

		table_.addSelectionListener(new class SelectionAdapter {
			override void widgetDefaultSelected(SelectionEvent e)
			{
				maybeOpenLink(cast(TableItem)e.item);
			}
		});

		table_.addKeyListener(new class KeyAdapter {
			override void keyPressed(KeyEvent e) {
				if (e.keyCode == 'c' && e.stateMask == SWT.MOD1)
					onCopyValue();
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

		table_.addListener(SWT.EraseItem, new class Listener {
			void handleEvent(Event e) {
				if (e.index == CvarColumn.VALUE)
					e.detail &= ~SWT.FOREGROUND;
			}
		});

		table_.addListener(SWT.PaintItem, new class Listener {
			void handleEvent(Event e) {
				if (e.index != CvarColumn.VALUE)
					return;

				auto item = cast(TableItem) e.item;
				auto text = item.getText(CvarColumn.VALUE);
				scope tl = new TextLayout(Display.getDefault);
				int index = table_.indexOf(item);
				auto range = ranges_[index];

				tl.setText(item.getText(CvarColumn.VALUE));

				if (range.hasLink) {
					auto linkColor = Display.getDefault()
					                    .getSystemColor(SWT.COLOR_BLUE);
					auto style = new TextStyle(null, linkColor, null);
					style.underline = true;
					tl.setStyle(style, range.first, range.last);
				}

				tl.draw(e.gc, e.x + 2, e.y + 2);
				tl.dispose();
			}
		});
	}

	Table getTable() { return table_; }  ///

	void setItems(string[][] items)  ///
	{
		table_.setRedraw(false);
		table_.setItemCount(0);
		ranges_.length = items.length;

		foreach (i, v; items) {
			TableItem item = new TableItem(table_, SWT.NONE);
      		item.setText(v);
			ranges_[i] = getLinkRange(v[CvarColumn.VALUE]);
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
	struct LinkRange { bool hasLink; int first; int last; }

	Table table_;
	Composite parent_;
	LinkRange[] ranges_;


	Menu createContextMenu()
	{
		Menu menu = new Menu(table_);

		MenuItem item = new MenuItem(menu, SWT.PUSH);
		item.setText("Open link\tEnter");
		menu.setDefaultItem(item);
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e) {
				if (table_.getSelectionCount > 0)
					maybeOpenLink(table_.getSelection()[0]);
			}
		});

		item = new MenuItem(menu, SWT.PUSH);
		item.setText("Copy value\tCtrl+C");
		item.addSelectionListener(new class SelectionAdapter {
			override void widgetSelected(SelectionEvent e) {
				onCopyValue();
			}
		});


		return menu;
	}

	LinkRange getLinkRange(const(char)[] s)
	{
		__gshared auto re = ctRegex!(
		    r"((((https?:\/\/)|(s?ftps?:\/\/))([-\w]+\.)?)|[-\w]+\.)[-\w]+\.[a-zA-Z]{2,}(\/[-/\w]+)?");
		auto m = s.matchFirst(re);

		if (!!m)
			return LinkRange(true, m.pre.length, s.length - m.post.length - 1);
		else
			return LinkRange(false);
	}

	void maybeOpenLink(TableItem item)
	{
		string s = item.getText(CvarColumn.VALUE);
		auto range = ranges_[table_.indexOf(item)];

		if (range.hasLink)
			Program.launch(s[range.first..range.last+1]);
	}

	void onCopyValue()
	{
		string s = table_.getItem(table_.getSelectionIndex())
		                                    .getText(CvarColumn.VALUE);
		copyToClipboard(s);
	}
}
