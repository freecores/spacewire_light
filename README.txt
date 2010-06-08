
SpaceWire Light
===============

Copyright 2009-2010 Joris van Rantwijk

SpaceWire Light is free software; you can redistribute it and/or
modify it under the terms of the GNU Lesser General Public License
as published by the Free Software Foundation; either version 2.1
of the License, or (at your option) any later version.

SpaceWire Light is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with the SpaceWire Light package. If not, see
<http://www.gnu.org/licenses/>.


Overview
--------

SpaceWire Light is a SpaceWire encoder-decoder with FIFO interface.
It is synthesizable for FPGA targets (up to 200 Mbit on Spartan-3).

The goal is to provide a complete, reliable, fast implementation
of a SpaceWire encoder-decoder according to ECSS-E-50-12C.
The core is "light" in the sense that it does not provide additional
features such as RMAP, routing etc.

This core would be very suitable for application in lab environments,
to add a SpaceWire interface to a custom FPGA design, and for interfacing
between existing SpaceWire equipment and a computer.

The project is currently very much in alpha phase. Most importantly,
there is no proper documentation. I WILL PROVIDE DOCUMENTATION SOON.

Short term plan:
 * more testing
 * documentation

Long term plan:
 * add AMBA bus interface


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
