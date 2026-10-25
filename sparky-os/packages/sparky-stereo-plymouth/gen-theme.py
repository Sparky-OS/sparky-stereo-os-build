#!/usr/bin/python3
# Builds sparky-stereo-lines.script from sparky-lines.script (read, never changed):
# the message, password and fsck code is kept as it is, with the sprites made per eye;
# the layout, the electrons and their depth are new.
# usage: gen-theme.py ORIGINAL_SCRIPT OUTPUT_SCRIPT [slope|height]
import re, sys

orig = open(sys.argv[1], encoding='utf-8').read().split('\n')
out_path = sys.argv[2]
depth = sys.argv[3] if len(sys.argv) > 3 else 'slope'

def L(a, b):
    """original lines a..b (1-based, inclusive)"""
    return '\n'.join(orig[a - 1:b]) + '\n'

def find(text, start=1):
    for i in range(start - 1, len(orig)):
        if text in orig[i]:
            return i + 1
    raise SystemExit('not found: ' + text)

colours_a = find('# Set the text colour in')
colours_b = find('# Orange - #ff4012') - 1
text_a = find('# General purpose function to create text')
text_b = find('fun Debug(text)') - 1
ytext_a = find('fun TextYOffset()')
ytext_b = find('#------------------------------String functions') - 1
str_a = ytext_b + 1
logo_fn_b = find('#-----------------------------------------Label utility functions') - 1
msg_a = logo_fn_b + 1
msg_b = find('#-----------------------------------------Message stuff') - 1
setup_a = find('fun setup_message')
cb_a = find('# the callback function is called when new message should be displayed.')
pw_a = find('#-----------------------------------------Display Password stuff')
nrm_a = find('#-----------------------------------------Display Normal stuff')

header = '''\
#  sparky-stereo-lines.script - the stereo sister of Sparky's lines boot splash
#
#  The original, sparky-lines, is part of the Sparky black set (Copyright
#  2018-2020 Pawel "pavroo" Pijanowski and Daniel Ramos); it is Debian 8's
#  lines theme (Juliette Taka Belin and Aurelien Couderc), made from Alberto
#  Milone's lines.script for Canonical and Charlie Brej's script plugin
#  example. It stays untouched; this theme keeps its message, password and
#  fsck code and uses its images.
#
#  What is new, written for Sparky Stereo OS (Daniel Ramos):
#   - the theme declares Stereo=full-side-by-side, and on a stereo output
#     Plymouth hands it both eyes side by side (Window.GetStereo () is then
#     true): the left eye in the left half, the right eye in the right half,
#     both from one animation clock; elsewhere it draws once, like the original;
#   - three levels, each item shifted by its own depth and drawn once per eye:
#     the background on the screen; the base, the swirl with its orbit lines,
#     one step in front of it; the SparkyOS logo (its swirl and the wordmark
#     SPARKYOS / POWERED BY DEBIAN / STEREO 3D EDITION) one more step in front,
#     standing on the raised base;
#   - the electrons ride the base's orbits, and each eye computes the path of an
#     electron from its own shifted point. Along a curve the electron pops where
#     the curve rises and sinks where it falls (DEPTH_FOLLOWS = "slope"), or pops
#     in the upper half and sinks in the lower half ("height"), a few pixels
#     either way from the base;
#   - the messages, password and progress are drawn in both eyes on the screen.
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2, or (at your option)
#  any later version.

#------------------------------- Constants -----------------------------------------
ELECTRONS_DISPLAYED = 3;
SECS_BETWEEN_ANIMS = 2.5;

# Depth of an electron, as parallax between the eyes in pixels at 1920 pixels per eye
# (scaled to the eye's width). Popped is smaller than sunk: a popped thing that nears
# the edge breaks the window, a sunk one does not.
DEPTH_FOLLOWS = "%(depth)s";
POP_PX = 4.0;
SINK_PX = 6.0;

# The levels, as parallax in front of the screen in pixels at 1920 pixels per eye (scaled to the eye's width):
# the base one step, the logo two. Two steps are the logo's raise in the SparkyOS stereo theme (sparkyos-stereo:
# 0.00473 of the eye's width, 9.08 px at 1920, measured in front of the background in a real stereo clip), so the
# logo stands one step above the base as the base stands one step above the screen.
STEP_PX = 4.54;
BASE_PX = STEP_PX;
LOGO_PX = 2 * STEP_PX;

#------------------------------- Globals -------------------------------------------
''' % {'depth': depth}

eyes = '''
#------------------------------- Eyes ----------------------------------------------
# On a stereo output the window holds both eyes side by side (the theme declares
# Stereo=full-side-by-side); anywhere else it is one picture and the theme draws it once,
# like the original.
win_width = Window.GetWidth ();
win_height = Window.GetHeight ();
if (Window.GetStereo ())
    EYES = 2;
else
    EYES = 1;
EYE_W = win_width / EYES;
EYE_H = win_height;
POP = POP_PX * EYE_W / 1920;
SINK = SINK_PX * EYE_W / 1920;
BASE = BASE_PX * EYE_W / 1920;
LOGO = LOGO_PX * EYE_W / 1920;

# A stereo sprite is one sprite per eye. d is the parallax in pixels, positive in front of
# the screen: the left eye's picture moves right by d / 2 and the right eye's left by d / 2.
# One eye (a 2D screen) draws every level in its place.
fun SS_New (image) {
    local.ss;
    ss.s[0] = Sprite (image);
    if (EYES == 2)
        ss.s[1] = Sprite (image);
    return ss;
}

fun SS_Place (ss, x, y, z, d) {
    local.e;
    local.half;
    for (e = 0; e < EYES; e++) {
        half = d / 2;
        if (EYES == 1)
            half = 0;
        if (e == 1)
            half = -half;
        ss.s[e].SetPosition (Math.Int (x + e * EYE_W + half + 0.5), Math.Int (y + 0.5), z);
    }
}

fun SS_Opacity (ss, opacity) {
    local.e;
    for (e = 0; e < EYES; e++)
        ss.s[e].SetOpacity (opacity);
}

fun SS_SetImage (ss, image) {
    local.e;
    for (e = 0; e < EYES; e++)
        ss.s[e].SetImage (image);
}

#------------------------------- Background ----------------------------------------
bg_image = Image("background.png");
# Scale the background to cover one eye. With two eyes it is scaled by the width, so that
# it never reaches into the other eye.
screen_ratio = EYE_W / EYE_H;
bg_image_ratio = bg_image.GetWidth() / bg_image.GetHeight();
if (EYES == 2 || screen_ratio > bg_image_ratio)
    bg_scale_factor = EYE_W / bg_image.GetWidth();
else
    bg_scale_factor = EYE_H / bg_image.GetHeight();
scaled_bg_image = bg_image.Scale(bg_image.GetWidth() * bg_scale_factor,
                                 bg_image.GetHeight() * bg_scale_factor);

# Display background
bg_sprite = SS_New(scaled_bg_image);
SS_Place(bg_sprite, EYE_W / 2 - scaled_bg_image.GetWidth() / 2,
                    EYE_H / 2 - scaled_bg_image.GetHeight() / 2,
                    -10000, 0);

#------------------------------- Base: the swirl and its orbits ----------------------
logo_image = Image("logo.png");
logo_height = Math.Min(EYE_W, EYE_H) * 0.7;
logo_scale_factor = logo_height / logo_image.GetHeight();
logo_image = logo_image.Scale(logo_image.GetWidth() * logo_scale_factor,
                              logo_image.GetHeight() * logo_scale_factor);
logo_sprite = SS_New(logo_image);
logo_to_top_edge = EYE_H * 0;
logo_right_shift = logo_image.GetWidth() * 0.092;
logo_x = EYE_W / 2 - logo_image.GetWidth() / 2 + logo_right_shift;
logo_y = logo_to_top_edge;
SS_Place(logo_sprite, logo_x, logo_y, -100, BASE);

#------------------------------- Logo: SPARKYOS / POWERED BY DEBIAN / STEREO 3D EDITION -
debian_image = Image("wordmark.png");
debian_width = logo_image.GetWidth();
debian_scale_factor = debian_width / debian_image.GetWidth() * 0.7;
if (debian_scale_factor < 1) {
    debian_image = debian_image.Scale(debian_image.GetWidth() * debian_scale_factor,
                                      debian_image.GetHeight() * debian_scale_factor);
}
debian_sprite = SS_New(debian_image);
debian_to_bottom_edge = EYE_H * 0.092;
debian_x = EYE_W / 2 - debian_image.GetWidth() / 2;
debian_y = EYE_H - debian_to_bottom_edge - debian_image.GetHeight();
SS_Place(debian_sprite, debian_x, debian_y, -90, LOGO);

#------------------------------- Electrons --------------------------------------------

electron_image = Image("electron.png");
electron_image = electron_image.Scale(
    electron_image.GetWidth() * 0.06 * logo_scale_factor,
    electron_image.GetHeight() * 0.06 * logo_scale_factor);


#main center coords
ellipses[0].x = logo_x + logo_image.GetWidth() * 0.4245;
ellipses[0].y = logo_y + logo_image.GetHeight() * 0.611;
#main small / large axis
ellipses[0].height = logo_image.GetHeight() * 0.3303;
ellipses[0].width = logo_image.GetWidth() * 0.295;
#main animation parameters
ellipses[0].anim.start_iter = 0;
ellipses[0].anim.stop_iter = 150;
ellipses[0].anim.start_angle = Math.Pi;
ellipses[0].anim.arc = 2*Math.Pi;
ellipses[0].anim.rotat_dir = -1;

#left center coords
ellipses[1].x = logo_x + logo_image.GetWidth() * 0.3825;
ellipses[1].y = logo_y + logo_image.GetHeight() * 0.411;
#left small / large axis
ellipses[1].height = logo_image.GetHeight() * 0.1645;
ellipses[1].width = logo_image.GetWidth() * 0.2248;
#left animation parameters
ellipses[1].anim.start_iter = 50;
ellipses[1].anim.stop_iter = 130;
ellipses[1].anim.start_angle = 0;
ellipses[1].anim.arc = 2*Math.Pi;
ellipses[1].anim.rotat_dir = 1;

#right center coords
ellipses[2].x = logo_x + logo_image.GetWidth() * 0.7065;
ellipses[2].y = logo_y + logo_image.GetHeight() * 0.460;
#right small / large axis
ellipses[2].height = logo_image.GetHeight() * 0.2343;
ellipses[2].width = logo_image.GetWidth() * 0.2945;
#right animation parameters
ellipses[2].anim.start_iter = 20;
ellipses[2].anim.stop_iter = 100;
ellipses[2].anim.start_angle = 0;
ellipses[2].anim.arc = 2*Math.Pi;
ellipses[2].anim.rotat_dir = 1;

# Define 5 stereo sprites for each electron to create gradient along the ellipses
for (i = 0; i < ELECTRONS_DISPLAYED; i++) {
    anim = ellipses[i].anim;
    anim.angle_incr = anim.arc / (anim.stop_iter - anim.start_iter) * anim.rotat_dir;
    for (j = 0; j < 5; j++) {
        electron_sprite[i][j] = SS_New(electron_image);
        SS_Opacity(electron_sprite[i][j], 0);
        electron_sprite[i][j].base_opacity = 1-(0.2*j);
        electron_sprite[i][j].angle_diff = -(anim.rotat_dir*j*0.01);
    }
}

# The animation clock: every frame of both eyes is drawn from it
anim_clock = 0;


'''

# globals of the original (prompt_active, anim_iter, anim_status)
globals_ = L(find('prompt_active = 0;') - 1, find('anim_status = "stopped";'))

tail = '''
#-----------------------------------------Refresh stuff --------------------------------
#
# Calling Plymouth.SetRefreshFunction with a function will set that function to be
# called up to 50 times every second. One call draws both eyes.
#
fun refresh_callback ()
{
    anim_clock++;

    if (global.anim_status == "start") {
        anim_iter = 0;
        for (i = 0; i < ELECTRONS_DISPLAYED; i++) {
            ellipses[i].anim.angle = ellipses[i].anim.start_angle;
        }
        global.anim_status = "running";
    }

    if (global.anim_status == "running") {
        anim_done = 1;
        for (i = 0; i < ELECTRONS_DISPLAYED; i++) {
            if (anim_iter >= ellipses[i].anim.start_iter && anim_iter < ellipses[i].anim.stop_iter) {
                draw_electron(i);

                ellipses[i].anim.angle += ellipses[i].anim.angle_incr;
                # check if at least one of the animations needs more loops
                if (ellipses[i].anim.stop_iter > anim_iter) {
                    anim_done = 0;
                }
            }
        }
        if (anim_done) {
            global.anim_status = "stopped";
        }
        anim_iter++;
    }
}
Plymouth.SetRefreshFunction (refresh_callback);

# Acceleration function to have the electrons move faster in there most visible section, in
# the middle of the ellipses.
#
# The function computes the result based on the .anim.angle member value in the given ellipse
#
# The angle is adapted so that accel([start_angle,start_angle+arc])->[start_angle,start_angle+arc]
# is traveled in a sin([0,Pi/2])->[0,1] manner instead of linear increments
#
fun compute_angle_with_accel(ellipse) {
    # first map the [start_angle,start_angle+arc] to [0,Pi/2]
    angle_in_0_pi_2 = Math.Pi / 2 / ellipse.anim.arc * (ellipse.anim.angle - ellipse.anim.start_angle);
    # then compute sin and scale output to [start_angle,start_angle+arc]
    accel_angle = ellipse.anim.arc * Math.Sin(angle_in_0_pi_2) + ellipse.anim.start_angle;
    return accel_angle;
}

# Computes the opacity factor so that the electrons visibility somehow matches that of the ellipses:
# Most visible in a middle part, and invisible at the oposite.
fun compute_opacity(ellipse) {
    # map the [start_angle,start_angle+arc] to [0,Pi]
    transformed_angle = Math.Pi / ellipse.anim.arc * (ellipse.anim.angle - ellipse.anim.start_angle);
    # and compute Math.Sin^2
    opacity_factor = Math.Sin(Math.Max(transformed_angle,-transformed_angle));
    opacity_factor *= opacity_factor;
    return opacity_factor;
}

# The depth of a point of an ellipse, as parallax in pixels (positive: in front of the screen).
# The point is x = a cos(phi), y = b sin(phi) from the centre, y down, and the electron moves
# in the direction rotat_dir.
# "slope": f is minus the vertical part of the direction of travel (a unit vector), so the
# electron is at its nearest where the curve rises steepest and at its farthest where it falls
# steepest, and at the screen where the curve is level.
# "height": f is minus the height over the centre in units of b: the upper half pops, the lower
# half sinks.
# Popped uses POP and sunk uses SINK, from the base the orbits are drawn on.
fun compute_depth (ellipse, phi) {
    local.f;
    local.tx;
    local.ty;
    local.length;

    if (DEPTH_FOLLOWS == "height") {
        f = -Math.Sin (phi);
    } else {
        tx = -ellipse.width * Math.Sin (phi);
        ty = ellipse.height * Math.Cos (phi);
        length = Math.Sqrt (tx * tx + ty * ty);
        f = -(ellipse.anim.rotat_dir * ty / length);
    }

    if (f >= 0)
        return BASE + POP * f;
    return BASE + SINK * f;
}

# Draw the 5 electron sprites to create a gradient effect, in both eyes
#
# The position is computed based on the .angle field, adapted with the acceleration function above;
# each eye gets it shifted by its half of the depth of that point of the curve.
#
fun draw_electron(index) {
    base_electron_x = ellipses[index].x - electron_image.GetWidth() / 2;
    base_electron_y = ellipses[index].y - electron_image.GetHeight() / 2;
    accel_angle = compute_angle_with_accel(ellipses[index]);
    opacity_factor = compute_opacity(ellipses[index]);
    for (j = 0; j < 5; j++) {
        phi = accel_angle + electron_sprite[index][j].angle_diff;
        electron_x = base_electron_x + ellipses[index].width * Math.Cos(phi);
        electron_y = base_electron_y + ellipses[index].height * Math.Sin(phi);
        SS_Opacity(electron_sprite[index][j], opacity_factor * electron_sprite[index][j].base_opacity);
        SS_Place(electron_sprite[index][j], electron_x, electron_y, -10, compute_depth(ellipses[index], phi));
    }
}


'''

parts = []
parts.append(header)
parts.append(globals_)
parts.append(eyes)
parts.append('\n' + L(colours_a, colours_b))
parts.append(L(text_a, text_b))
y = L(ytext_a, ytext_b)
y = y.replace('logo_sprite.GetY()', 'logo_y').replace('debian_sprite.GetY()', 'debian_y')
parts.append(y)
parts.append(L(str_a, logo_fn_b))
m = L(msg_a, msg_b)
m = m.replace('Window.GetX () + Window.GetWidth () / 2', 'EYE_W / 2')
parts.append(m)
parts.append('''#-----------------------------------------Message stuff --------------------------------
#

# Set up a message label
#
# NOTE: this is called when doing something like 'plymouth message "hello world"'
#
fun setup_message (message_text, x, y, z, index) {
    global.message_notification[index].image = (index) && ImageFromActionText (message_text) || ImageFromTintedText (message_text);

    # Set up the text message, if any
    message_notification[index].x = x;
    message_notification[index].y = y;
    message_notification[index].z = z;

    message_notification[index].sprite = SS_New (message_notification[index].image);
    SS_Place (message_notification[index].sprite, x, y, z, 0);

}

fun show_message (index) {
    if (global.message_notification[index].sprite) SS_Opacity (global.message_notification[index].sprite, 1);
}

fun hide_message (index) {
    if (global.message_notification[index].sprite) SS_Opacity (global.message_notification[index].sprite, 0);
}




''')
parts.append(L(cb_a, nrm_a - 1 if False else find('#-----------------------------------------Refresh stuff') - 1))
mid_text = ''.join(parts[-1:])
# remove the verbatim refresh section and the original electron code from the verbatim part: it ends before Refresh stuff
body = ''.join(parts[:-1])
verb = parts[-1]

# sprite edits in the verbatim part (message callback, password, fsck, status)
def sub(pattern, repl, text, count=None):
    new, n = re.subn(pattern, repl, text)
    if n == 0:
        raise SystemExit('no match for ' + pattern)
    return new

verb = sub(r'entry\.sprite = Sprite \(\);\n\s*entry\.sprite\.SetImage \(entry\.image\);', 'entry.sprite = SS_New (entry.image);', verb)
verb = verb.replace('entry.x = Window.GetX () + Window.GetWidth () / 2 - entry.image.GetWidth () / 2;', 'entry.x = EYE_W / 2 - entry.image.GetWidth () / 2;')
verb = sub(r'entry\.sprite\.SetX \(entry\.x\);\n\s*entry\.sprite\.SetY \(entry\.y\);\n\s*entry\.sprite\.SetZ \(entry\.z\);',
           'SS_Place (entry.sprite, entry.x, entry.y, entry.z, 0);', verb)
verb = verb.replace('bullets_area.x = Window.GetX () + Window.GetWidth () / 2 - bullets_area.width / 2;', 'bullets_area.x = EYE_W / 2 - bullets_area.width / 2;')
verb = sub(r'password_dialogue\.bullets\[index\]\.sprite = Sprite \(\);\n\s*password_dialogue\.bullets\[index\]\.sprite\.SetImage \(password_dialogue\.bullet_image\);',
           'password_dialogue.bullets[index].sprite = SS_New (password_dialogue.bullet_image);', verb)
verb = sub(r'\n\s*password_dialogue\.bullets\[index\]\.sprite\.SetX \(password_dialogue\.bullets\[index\]\.x\);', '', verb)
verb = sub(r'\n\s*password_dialogue\.bullets\[index\]\.sprite\.SetY \(password_dialogue\.bullets\[index\]\.y\);', '', verb)
verb = sub(r'password_dialogue\.bullets\[index\]\.sprite\.SetZ \(password_dialogue\.bullets\[index\]\.z\);',
           'SS_Place (password_dialogue.bullets[index].sprite, password_dialogue.bullets[index].x, password_dialogue.bullets[index].y, password_dialogue.bullets[index].z, 0);', verb)
verb = sub(r'(\S+)\.sprite\.SetOpacity\s*\(([^;]*)\)\s*;', r'SS_Opacity (\1.sprite, \2);', verb)
verb = sub(r'Sprite \(progress_label\.image\)', 'SS_New (progress_label.image)', verb)
verb = sub(r'progress_label\.sprite\.SetPosition\(progress_label\.x, progress_label\.y, 1\);',
           'SS_Place (progress_label.sprite, progress_label.x, progress_label.y, 1, 0);', verb)

normal = L(find('#-----------------------------------------Display Normal stuff'), len(orig))

result = body + verb + tail + normal
open(out_path, 'w', encoding='utf-8').write(result)
print('wrote', out_path, result.count('\n'), 'lines')
