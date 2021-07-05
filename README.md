# AVmagick
This is simple script that I use to synchronize the audio recording from a 
good microphone to the video recording of the same scene.

The difficult part of the work is done by the `align.py` script that was 
written by [Allison Deal](https://github.com/allisonnicoledeal/VideoSync)
and by ffmpeg [ffmpeg](http://ffmpeg.org). 
My  `automix.rb` script is just a wrapper that I wrote just because I am too 
lazy for doing things by hand and because I never remember the command line 
syntax for ffmpeg.

### Requirements:
 - ruby interpreter with `imgkit` gem
 - python interpreter with `nympy` and `scipy`
 - a recent version of [ffmpeg](http://ffmpeg.org)
 - [ImageMagick](https://www.imagemagick.org/)

### Usage:

The ingredients are:
 - one or more video files
 - one or more audio files
 - an `input.yml` describing how to combine them;
 - optionally a title template file (e.g. `title.html.erb`);

For both input files there is an example in the `examples` directory that you 
can rename and edit.

In principle, once the input file `input.yml` is ready, all you have to do is
to execute `automix.rb`:

```
ruby automix.rb

```

In reality sometimes the alignemen of video and audio is not perfect. In this
case, you have to try to change a bit the `vc` parameter.
In the workdir, there is a file called `SOMETHING_s.wav` where the two audio
channels contain the (crappy) audio from the video recording and the (good) 
audio from the audio-recorder respectively. Listening to this is a fast way
to check if the alignement is correct.

#### Title pages
If you want to prepend a title page to your video, you can set the following two
parameters in your input file:
```
title: DURATION_IN_SECONDS
template: title.html.erb
```

and, foreach video:

```
    title:
      composer: "Antonin DVORAK"
      title: "Sonatine op. 100"
      desc: "1<sup>er</sup> movement: <em>Allegro risoluto</em>"
      artist: "Ciccio Pasticcio and Pierino Paperino (violin), Nonna Papera (alto), Donald Duck (cello)"
      short: "DVORAK: Sonatine op. 100 / 1. Allegro risoluto"
```
where the various parameters (`composer`, `title`) are totally arbitrary and
only depend on the variables that you want to expand to generate the title page
for that particular video.
The example `examples/title.html.erb` should be quite clear. Since it is 
standard html, you can style it as you like.
The only *hardcoded* parameter is `short` that is used to generate a video 
description with chapter markers that can be copy/pasted directly to youtube.

### Other similar projects
 - https://github.com/align-videos-by-sound/align-videos-by-sound
 - https://write.as/hammertoe/aligning-audio-files-in-python
