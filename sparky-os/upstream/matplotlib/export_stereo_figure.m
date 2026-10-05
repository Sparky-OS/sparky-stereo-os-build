function export_stereo_figure(fig, filename, eye_separation, screen_distance)
  if nargin < 3 || isempty(eye_separation)
    eye_separation = 65;
  endif
  if nargin < 4 || isempty(screen_distance)
    screen_distance = 350;
  endif

  axes_handle = get(fig, "children");
  if numel(axes_handle) ~= 1
    error("figure must contain exactly one axes");
  endif
  if ~strcmp(get(axes_handle, "projection"), "perspective")
    error("stereo parallax needs a perspective projection: set(axes, \"projection\", \"perspective\")");
  endif
  original_position = get(fig, "position");
  original_axes_units = get(axes_handle, "units");
  original_axes_position = get(axes_handle, "position");
  original_camera = camera_settings(axes_handle);
  original_view = get(axes_handle, "view");
  original_view_angle = camva(axes_handle);

  try
    % The view angle has no lens shift: the camera keeps its angle and the
    % figure is made wider by a margin on each side, then every eye is cropped
    % by an offset.  The camera angle spans the axes' height, so the scale in
    % pixels does not change when the figure is widened.
    set(axes_handle, "units", "pixels");
    axes_pixels = get(axes_handle, "position");
    distance = norm(original_camera.camtarget - original_camera.campos);
    focal = (axes_pixels(4) / 2) / tand(original_view_angle / 2);
    % The baseline scales with the camera distance, as in mpl_parallel_stereo.py;
    % the screen-plane offset is rounded to whole pixels so the crop is exact.
    offset = round(eye_separation / (2 * screen_distance) * focal);
    half_baseline = offset * distance / focal;
    margin = offset + 1;
    full_width = original_position(3);
    set(fig, "position", [original_position(1:2), full_width + 2 * margin, ...
                           original_position(4)]);
    set(axes_handle, "position", [axes_pixels(1) + margin, axes_pixels(2:4)]);
    left = render_eye(axes_handle, -half_baseline, original_camera);
    right = render_eye(axes_handle, half_baseline, original_camera);
    restore_camera(axes_handle, original_camera, original_view, ...
                   original_view_angle);
    set(fig, "position", original_position);
    set(axes_handle, "units", original_axes_units);
    set(axes_handle, "position", original_axes_position);
    % The left camera sits to the left, so the point at the target shows to
    % the right of centre there and the crop window moves right with it.
    left = left(:, margin+offset+1:margin+offset+full_width, :);
    right = right(:, margin-offset+1:margin-offset+full_width, :);
    stereo = [left, right];
    write_image(stereo, filename);
  catch err
    restore_camera(axes_handle, original_camera, original_view, ...
                   original_view_angle);
    set(fig, "position", original_position);
    set(axes_handle, "units", original_axes_units);
    set(axes_handle, "position", original_axes_position);
    rethrow(err);
  end_try_catch
endfunction

function settings = camera_settings(axes_handle)
  settings = struct();
  settings.campos = campos(axes_handle);
  settings.camtarget = camtarget(axes_handle);
  settings.camup = camup(axes_handle);
endfunction

function eye = render_eye(axes_handle, half_separation, original)
  view_vector = original.camtarget - original.campos;
  right = cross(view_vector, original.camup);
  right /= norm(right);
  campos(axes_handle, original.campos + half_separation * right);
  camtarget(axes_handle, original.camtarget + half_separation * right);
  drawnow();
  eye = capture_figure(axes_handle);
endfunction

function restore_camera(axes_handle, settings, original_view, view_angle)
  campos(axes_handle, settings.campos);
  camtarget(axes_handle, settings.camtarget);
  camup(axes_handle, settings.camup);
  view(axes_handle, original_view);
  camva(axes_handle, view_angle);
  drawnow();
endfunction

function pixels = capture_figure(axes_handle)
  fig = ancestor(axes_handle, "figure");
  filename = [tempname(), ".png"];
  print(fig, filename, "-r0");
  pixels = imread(filename);
  unlink(filename);
  fig_position = get(fig, "position");
  pixels = pixels(1:fig_position(4), 1:fig_position(3), :);
endfunction

function write_image(pixels, filename)
  [~, ~, extension] = fileparts(filename);
  switch lower(extension)
    case ".jpg"
      imwrite(pixels, filename, "jpg");
    case ".jpeg"
      imwrite(pixels, filename, "jpeg");
    case ".png"
      imwrite(pixels, filename, "png");
    otherwise
      error("filename must end in .jpg, .jpeg, or .png");
  endswitch
endfunction
