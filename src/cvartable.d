module cvartable;

import org.eclipse.swt.SWT;
import org.eclipse.swt.widgets.Composite;
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
		table_ = new Table(parent_, SWT.BORDER);
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
	}

	Table getTable() => table_;  ///

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
}
