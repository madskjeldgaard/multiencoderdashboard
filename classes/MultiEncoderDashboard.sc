MultiEncoderDashboard {
	classvar dashboards;

	var quarkpath;

	*initClass{

		//this method makes sure that the IDict is compiled before
		//trying to make an instance of it
		Class.initClassTree(Ndef);

	}

	*new { | numPanels=1, closeAble=false|
		^super.new.init( numPanels, closeAble);
	}

	init { | numPanels=1, closeAble=false |
		var dashboard;

		dashboards = Array.new(numPanels);

		quarkpath = Quark("multiencoderdashboard").localPath;

		dashboard = quarkpath +/+ "iem-encoder-dashboard.scd";
		dashboard = dashboard.load;

		dashboard = dashboard.value(numPanels, closeAble);

		// dashboards = dashboard;

	}

	*dashboards{ ^dashboards }

	*addDashboard{|dashboard|
		dashboards = dashboard;

		^dashboards
	}

}
