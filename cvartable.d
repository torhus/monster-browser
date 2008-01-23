module cvartable;

private {
	version (Windows)
		import dwt.all;
	else {
		import dwt.DWT;
		import dwt.widgets.Composite;
		import dwt.widgets.Table;
		import dwt.widgets.TableColumn;
		import dwt.widgets.TableItem;
	}

	import common;
	import serverlist;
	import main;
}

class CvarTable
{
	/*************************************************
	               PUBLIC METHODS
	*************************************************/
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


		table_.getColumn(0).setWidth(90);
		table_.getColumn(1).setWidth(90);
	}

	Table getTable() { return table_; }

	void setItems(char[][][] items)
	{
		assert (items && items.length);
		table_.setItemCount(0);
		foreach (v; items) {
			TableItem item = new TableItem(table_, DWT.NONE);
      		item.setText(v);
      	}
  	}

	void clear()
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
