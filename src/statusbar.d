module statusbar;

import std.algorithm : each;
import std.conv;

import org.eclipse.swt.SWT;
import org.eclipse.swt.layout.GridLayout;
import org.eclipse.swt.layout.GridData;
import org.eclipse.swt.widgets.Composite;
import org.eclipse.swt.widgets.Label;
import org.eclipse.swt.widgets.ProgressBar;

import common;
version (Windows) import mswindows.taskbarprogress;


__gshared StatusBar statusBar;  ///


///
final class StatusBar : Composite
{
	///
	this(Composite parent)
	{
		super(parent, SWT.NONE);
		auto layout = new GridLayout(7, false);
		layout.marginWidth = 2;
		layout.marginHeight = 0;
		setLayout(layout);

		progressLabel_ = new Label(this, SWT.NONE);
		progressLabel_.setVisible(false);

		progressBar_ = createProgressBar(false);
		progressBar_.setVisible(false);

		// an empty Label to push the rest of the labels to the far right of
		// the status bar
		auto empty = new Label(this, SWT.NONE);
		auto emptyData = new GridData(SWT.CENTER, SWT.CENTER, true, false);
		empty.setLayoutData(emptyData);

		int sepHeight = progressLabel_.computeSize(SWT.DEFAULT, SWT.DEFAULT).y;

		createSeparator(sepHeight);

		serverLabel_ = new Label(this, SWT.NONE);
		auto serverData = new GridData(SWT.CENTER, SWT.CENTER, false, false);
		serverLabel_.setLayoutData(serverData);

		createSeparator(sepHeight);

		playerLabel_ = new Label(this, SWT.NONE);
		auto playerData = new GridData(SWT.CENTER, SWT.CENTER, false, false);
		playerLabel_.setLayoutData(playerData);

		version (Windows) {
			initTaskbarProgress();
		}
	}

	void setLeft(string text)  ///
	{
		if (progressLabel_.isDisposed())
			return;
		progressLabel_.setText(text);
		layout();
	}

	void setDefaultStatus(uint totalServers, uint shownServers,
	                                            uint noReply, uint humans)  ///
	{
		if (isDisposed())
			return;

		setRedraw(false);

		string s;

		if (shownServers != totalServers)
			s = text(shownServers, " of ", totalServers, " servers");
		else
			s = text(shownServers, " servers");

		serverLabel_.setText(s);
		playerLabel_.setText(text(humans, " human players"));

		layout();
		setRedraw(true);
	}


	override void setToolTipText(string s) ///
	{
		super.setToolTipText(s);
		getChildren().each!(child => child.setToolTipText(s));
	}


	void showProgress(string label, bool indeterminate=false, int total=0,
	                                                        int progress=0)
	{
		if (isDisposed())
			return;

		assert(progressBar_ !is null);

		if ((progressBar_.getStyle() & SWT.INDETERMINATE) != indeterminate) {
			// remove the old ProgressBar, insert a new one
			progressBar_.dispose();
			progressBar_ = createProgressBar(indeterminate);
			progressBar_.moveBelow(progressLabel_);
			layout();
		}

		version (Windows) if (tbProgress_) {
			if (indeterminate) {
				tbProgress_.setProgressState(TBPF_INDETERMINATE);
			}
			else {
				tbProgress_.setProgressState(TBPF_NORMAL);
				tbProgress_.setProgressValue(progress, total);
			}
		}

		setProgressLabel(label);
		progressBar_.setState(SWT.NORMAL);
		progressBar_.setMaximum(total);
		progressBar_.setSelection(progress);
		progressLabel_.setVisible(true);
		progressBar_.setVisible(true);
	}


	void hideProgress(string text="")
	{
		if (isDisposed())
			return;
		progressBar_.setVisible(false);
		version (Windows) if (tbProgress_)
				tbProgress_.setProgressState(TBPF_NOPROGRESS);
		setLeft(text);
	}


	private void setProgressLabel(string text)
	{
		setLeft(text ~ "...");
	}


	void setProgress(int total, int current)
	{
		if (progressBar_.isDisposed())
			return;

		progressBar_.setMaximum(total);
		progressBar_.setSelection(current);

		version (Windows) if (tbProgress_) {
			if (!(progressBar_.getStyle() & SWT.INDETERMINATE))
				tbProgress_.setProgressValue(current, total);
		}
	}


	void setProgressError()
	{
		if (isDisposed())
			return;

		progressBar_.setState(SWT.ERROR);

		version (Windows) if (tbProgress_)
			tbProgress_.setProgressState(TBPF_ERROR);
	}


	private ProgressBar createProgressBar(bool indeterminate)
	{
		auto pb = new ProgressBar(this, indeterminate ?
		                                        SWT.INDETERMINATE : SWT.NONE);
		auto data = new GridData;
		data.widthHint = 100;
		pb.setLayoutData(data);
		return pb;
	}


	private Label createSeparator(int height)
	{
		auto sep = new Label(this, SWT.SEPARATOR);
		auto sepData = new GridData(SWT.CENTER, SWT.CENTER, false, false);
		sepData.heightHint = height;
		//sepData.widthHint = 5;
		sep.setLayoutData(sepData);
		return sep;
	}


	// For the Windows 7 and later taskbar.
	version (Windows) private void initTaskbarProgress()
	{
		try {
			tbProgress_ = new TaskbarProgress(parent.getShell().handle);
		}
		catch (Exception e) {
			//logx(__FILE__, __LINE__, e);
		}

		if (tbProgress_)
			callAtShutdown ~= &tbProgress_.dispose;
	}


private:
	Label serverLabel_;
	Label playerLabel_;
	Label progressLabel_;
	ProgressBar progressBar_;
	version (Windows) {
		TaskbarProgress tbProgress_ = null;
	}
}
