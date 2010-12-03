
SpaceWire Light
===============

Copyright 2009-2010 Joris van Rantwijk

SpaceWire Light is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

SpaceWire Light is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with the SpaceWire Light package. If not, see <http://www.gnu.org/licenses/>.


Overview
--------

SpaceWire Light is a SpaceWire encoder-decoder.
It is synthesizable for FPGA targets (up to 200 Mbit on Spartan-3).
Application interfaces include a simple FIFO interface, as well as
an AMBA bus interface for LEON3 system-on-chip designs.

The goal is to provide a complete, reliable, fast implementation
of a SpaceWire encoder-decoder according to ECSS-E-ST-50-12C.
The core is "light" in the sense that it does not provide additional
features such as RMAP, routing etc.

See doc/Manual.pdf for more information.

Future plans:
 * redesign fast receiver to improve performance
 * add support for Xilinx Virtex platform


Version history
---------------

2010-12-03
 * Add RTEMS driver and test program for SPWAMBA.
 * Add documentation for SPWAMBA.
 * spwamba: Change TX FIFO management; start new transfer when there is room
   for a maximum burst instead of aiming for 3/4 fill rate.
 * spwamba: Do not reset spwxmit in response to software reset.
 * spwamba: Fix bug in maximum burst size calculation.
 * spwamba: Optimize address generation in burst state machine.
 * spwamba: More careful calculation of RX credit.

2010-09-21
 * Add AMBA interface (preliminary version, untested, undocumented).
 * License changed from LGPL to GPL.
 * Again fix an issue with EEP injection on link loss.
 * Add DATAPATHONLY keyword to timing constraints.

2010-09-12
 * Fixed issue with automatic discarding of TX data after link error.
 * After link error, spwstream will terminate current packet with EEP even
   if the linkdisable signal is active.
 * Added code comment to clarify a dependency between spwrecv and spwlink.
   (Thanks to Rafael Corsi Ferrao for reporting this obscurity.)

2010-07-12
 * Added manual.
 * Fix incorrect bitrate during link handshake. The system clock frequency
   was used to compute the initial tx clock divider, even when the clock
   divider would act on the txclk instead of the system clock.
 * Improve fast transmitter. Sending FCT tokens at high bit rate no longer
   causes insertion of a NULL token.

2010-06-08
 * Initial release.


Contact
-------

For the latest version of this core, see the OpenCores project page.

For more information, comments, suggestions or bug reports, either
go to the OpenCores project page or email me directly.

Project page at OpenCores:
  http://opencores.org/project,spacewire_light

Email:
  jvrantwijk (at) xs4all (dot) nl

--
