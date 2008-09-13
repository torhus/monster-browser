module cvartable;

import dwt.DWT;
import dwt.widgets.Composite;
import dwt.widgets.Table;
import dwt.widgets.TableColumn;
import dwt.widgets.TableItem;

import common;
import main;
import serverlist;
import settings;


///
class CvarTable
{
	///
	this(Composite parent)
	{
		parent_ = parent;
		table_ = new Table(parent_, DWT.BORDER);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		TableColumn column = new TableColumn(table_, DWT.HIDE_SELECTION);
		column.setText("Key");
		column = new TableColumn(table_, DWT.NONE);
		column.setText("Value");

		int[] widths = parseIntegerSequence(
		                                  getSessionState("cvarColumnWidths"));
		// FIXME use defaults if wrong length?
		widths.length = 2;

		// add columns
		table_.getColumn(0).setWidth(widths[0]);
		table_.getColumn(1).setWidth(widths[1]);
	}

	Table getTable() { return table_; }  ///

	void setItems(char[][][] items)  ///
	{
		table_.setItemCount(0);
		foreach (v; items) {
			TableItem item = new TableItem(table_, DWT.NONE);
      		item.setText(v);
      	}
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
