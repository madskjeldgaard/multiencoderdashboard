MultiEncoderDashboardTest1 : UnitTest {
	test_check_classname {
		var result = MultiEncoderDashboard.new;
		this.assert(result.class == MultiEncoderDashboard);
	}
}


MultiEncoderDashboardTester {
	*new {
		^super.new.init();
	}

	init {
		MultiEncoderDashboardTest1.run;
	}
}
