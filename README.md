Tokyo Xtreme Racer Extractor
============================

TXRExtractor is an archive unpacker for GENKI Tokyo Xtreme Racer series games.
Currently supported archive extraction include WMN.DAT and AUDIO_PS3.DAT from Wangan Midnight PS3.

Wangan Midnight uses zlib deflate chunks that inflate up to 256KB and files are
composed of them. See relevant header files for reverse engineered headers and their description.

## NOTES

VC2013 was used to create project. Currently win32 target is only supported.
You need to have copy of a game or archives to attempt to extract them.

## Status

* Wangan Midnight 2007 PS3......................: WMN.DAT [ok], AUDIO_PS3.DAT [ok]
* Import Tuner Challenge 2006 Xbox 360...: [wip]

## Usage

From console:

     TXRExtractor.exe <archive> <table of content> <output>


## Goal


The goal of the project is to be able to import 3d models of Shuto expressway into
other environments such as GTA IV or standalone game engine.