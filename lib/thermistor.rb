# $Id$
# Thermistor calculations
require 'pp'

class Thermistor

  def cToK(c)
    c + 273.15
  end

  def kToC(k)
    k - 273.15
  end

  def initialize(_r0, _t0, _beta)
    @r0 = _r0
    @t0 = _t0
    @beta = _beta
  end

  def temperatureFromResistance(r)
    kToC(@beta/(Math::log(r/@r0)+(@beta/cToK(@t0))))
  end

  def resistanceFromTemperature(t)
    @r0 * Math::exp(@beta/(cToK(t))-@beta/(cToK(@t0)))
  end

end

if __FILE__ == $0

# quick sanity check
# using Murata NCPxxWF104 100K R0 4250K beta table

  Ro = 100.0e3
  To = 25.0
  Beta = 4250.0
  Rref = 36000.0

 MurataTable = [[ -40 , 4397.119 ], [ -35, 3088.599 ], [ -30, 2197.225 ], [ -25, 1581.881 ],
 [ -20, 1151.037 ], [ -15, 846.579 ], [ -10, 628.988 ], [ -5, 471.632 ], [ 0, 357.012 ],
 [ 5, 272.500 ], [ 10, 209.710 ], [ 15, 162.651 ], [ 20, 127.080 ], [ 25, 100.000 ],
 [ 30, 79.222 ], [ 35, 63.167 ], [ 40, 50.677 ], [ 45, 40.904 ], [ 50, 33.195 ],
 [ 55, 27.091 ], [ 60, 22.224 ], [ 65, 18.323 ], [ 70, 15.184 ], [ 75, 12.635 ],
 [ 80, 10.566 ], [ 85, 8.873 ], [ 90, 7.481 ], [ 95, 6.337 ], [ 100, 5.384 ],
 [ 105, 4.594 ], [ 110, 3.934 ], [ 115, 3.380 ], [ 120, 2.916 ], [ 125, 2.522 ]]

  OurTableValues = [37319,35463,33711,32057,30495,29019,27623,26303,25055,23874,22756,21697,20694,19743,18842,17988,17178,16409,15679,14986,14328,13703,13109,12544,12007,11496,11010,10547,10107,9688,9288,8907,8544,8198,7868,7554,7253,6967,6693,6432,6182,5943,5715,5498,5289,5090]
  OurTLow = 15
  OurTHigh = 60
  OurTMultiplier = 2**13
  OurTable = (OurTLow .. OurTHigh).to_a.zip(OurTableValues).collect { |a| [a[0], a[1].to_f * Rref/(OurTMultiplier*1000.0)] }

  t = Thermistor.new(Ro, To, Beta)
  printf("R=%f T=%f\n", Ro, t.temperatureFromResistance(Ro));
  printf("R=%f T=%f\n", t.resistanceFromTemperature(To), To);

  printf("%10s %10s %10s %10s %10s %10s\n", 'T', 'R', 'nom', 'error(C)', 'ourR', 'error(C)')
  MurataTable.each do |values|
    temperature = values[0]
    nominal = values[1]
    r = t.resistanceFromTemperature(temperature)
    measuredT = t.temperatureFromResistance(nominal * 1000.0)
    printf("%10d %10.2f %10.2f %10.2f", temperature, r/1000.0, nominal, measuredT - temperature)
    ours = OurTable.assoc(temperature)
    if ours
      ourR = ours[1]
      measuredT = t.temperatureFromResistance(ourR* 1000.0)
      printf("%10.2f %10.2f\n", ourR, measuredT - temperature)
    else
      print("\n")
    end
  end

end
