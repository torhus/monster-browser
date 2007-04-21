module cvartable;

private {
	import dejavu.lang.String;

	import org.eclipse.swt.SWT;
	import org.eclipse.swt.widgets.Composite;
	import org.eclipse.swt.widgets.Table;
	import org.eclipse.swt.widgets.TableColumn;
	import org.eclipse.swt.widgets.TableItem;

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
		table_ = new Table(parent_, SWT.BORDER);
		table_.setHeaderVisible(true);
		table_.setLinesVisible(true);

		TableColumn column = new TableColumn(table_, SWT.HIDE_SELECTION);
		column.setText(new String("Key"));
		column = new TableColumn(table_, SWT.NONE);
		column.setText(new String("Value"));


		table_.getColumn(0).setWidth(90);
		table_.getColumn(1).setWidth(90);
	}

	Table getTable() { return table_; }

	void setItems(char[][][] items)
	{
		assert (items && items.length);
		table_.setItemCount(0);
		foreach (v; items) {
			TableItem item = new TableItem(table_, SWT.NONE);
			foreach (i, s; v) {
      			item.setText(i, String.fromUtf8(s));
  			}
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
