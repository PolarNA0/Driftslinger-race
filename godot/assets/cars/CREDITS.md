# Car sprite credits

Every sprite here is free top-down car art under CC0 1.0 Universal (public domain
dedication), so attribution is optional. It is given anyway, because the authors
asked for it and it is the decent thing to do.

## `topdown_car.png` (Roadster)

- Pack: **TopDownCar_1** by **looneybits**
- Source: OpenGameArt - https://opengameart.org/content/topdowncar1
- Licence: CC0 1.0 Universal (public domain dedication)

The source art faces right (+X). It was rotated a quarter turn counter-clockwise
so the nose points up (-Y), matching the vector cars, which are drawn nose-first
along -Y. No other change was made.

## `topdown_car_red.png` (Redline)

- Pack: **Free Top-Down Car Sprites** by **UnLuckY Studio**
- Source: OpenGameArt -
  https://opengameart.org/content/free-top-down-car-sprites-by-unlucky-studio
- Licence: CC0 1.0 Universal (public domain dedication)

Taken from the pack's `Car.png` (the red car). It is stored nose-up already, so
only the transparent margin was trimmed; the art itself is unchanged.

## `topdown_car_viper.png`, `topdown_car_taxi.png`, `topdown_car_truck.png`

- Pack: **Free Top-Down Car Sprites** by **UnLuckY Studio** (same pack as above)
- Source: OpenGameArt -
  https://opengameart.org/content/free-top-down-car-sprites-by-unlucky-studio
- Licence: CC0 1.0 Universal (public domain dedication)

From the pack's `Black_viper.png` (Viper), `taxi.png` (Cab) and
`Mini_truck.png` (Hauler). All three are stored nose-up, so only the transparent
margin was trimmed.

Every sprite is trimmed to its opaque bounding box plus a two-pixel margin, so it
scales predictably; `render.gd` scales width from the sprite's own aspect ratio.

The vector cars (`Sunbeam`, `Ember`, `Mint`, `Cobalt`, `Orchid`, `Frost`,
`Graphite`, `Coral`) are drawn in code and need no assets.

