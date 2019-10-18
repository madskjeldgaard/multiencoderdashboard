MultiEncoderDashboard {
	var quarkpath;

	*new { | numPanels=1, closeAble=false|
		^super.new.init( numPanels=1, closeAble=false );
	}

	init { | numPanels=1, closeAble=false |
		var dashboard;
		quarkpath = Quark("multiencoderdashboard").localPath;

		dashboard = quarkpath +/+ "iem-encoder-dashboard.scd";
		dashboard = dashboard.load;

		^dashboard.value(numPanels, closeAble)
	}
}
