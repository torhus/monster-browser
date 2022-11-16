module swtutil;

import org.eclipse.swt.SWT;
import org.eclipse.swt.widgets.Menu;
import org.eclipse.swt.widgets.MenuItem;


private string[MenuItem] menuItemRegistry;

class RegistryException : Exception
{
    this(string msg) { super(msg); }
}


///
MenuItem addItem(Menu menu, string text, int style=SWT.NONE)
{
    auto item = new MenuItem(menu, style);
    item.setText(text);
    return item;
}

///
MenuItem addSeparator(Menu menu) {
    return new MenuItem(menu, SWT.SEPARATOR);
}

///
void register(MenuItem item, string name)
{
    menuItemRegistry[item] = name;
}

///
string lookUp(MenuItem item)
{
    auto p = item in menuItemRegistry;
    if (p is null)
        throw new RegistryException("Item not found.");
    return *p;
}
