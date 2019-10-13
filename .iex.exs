:observer.start
alias MAVLink.Router, as: MAV
vfr_hud = %APM.Message.VfrHud{
  airspeed: 0.0,
  alt: 43.43000030517578,
  climb: -0.6640441417694092,
  groundspeed: 0.5645657181739807,
  heading: 306,
  throttle: 0
}
MAV.subscribe message: APM.Message.VfrHud
MAV.pack_and_send vfr_hud
flush
