function prove_octave_stereo(output)
  if nargin < 1
    output = "octave-stereo.png";
  endif
  close all;
  fig = figure("visible", "off", "position", [0, 0, 300, 200]);
  ax = axes("parent", fig);
  hold(ax, "on");
  plot3(ax, 0, 0, 0, "o", "markerfacecolor", [1, 0, 0], "markeredgecolor", [1, 0, 0]);
  plot3(ax, 0.5, -3, 0.3, "o", "markerfacecolor", [0, 1, 0], "markeredgecolor", [0, 1, 0]);
  plot3(ax, -0.5, 5, -0.3, "o", "markerfacecolor", [0, 0, 1], "markeredgecolor", [0, 0, 1]);
  set(ax, "xlim", [-2, 2], "ylim", [-6, 6], "zlim", [-2, 2]);
  set(ax, "dataaspectratio", [1, 1, 1]);
  set(ax, "projection", "perspective");
  set(ax, "cameraposition", [0, -10, 0]);
  set(ax, "cameratarget", [0, 0, 0]);
  set(ax, "cameraupvector", [0, 0, 1]);
  set(ax, "cameraviewangle", 30);
  set(ax, "visible", "off");

  export_stereo_figure(fig, output);
  stereo = imread(output);
  width = size(stereo, 2) / 2;
  left = stereo(:, 1:width, :);
  right = stereo(:, width+1:end, :);
  names = {"centre", "near", "far"};
  colours = {[255, 0, 0], [0, 255, 0], [0, 0, 255]};
  verification = struct("stereo", [size(stereo, 2), size(stereo, 1)]);
  for k = 1:3
    a = centroid(left, colours{k});
    b = centroid(right, colours{k});
    verification.(names{k}) = struct("left", a, "right", b, "disparity", a - b);
  endfor
  verification.centre_x_zero = verification.centre.disparity(1) == 0;
  verification.near_x_positive = verification.near.disparity(1) > 0;
  verification.far_x_negative = verification.far.disparity(1) < 0;
  verification.vertical_zero = all([verification.centre.disparity(2), ...
                                    verification.near.disparity(2), ...
                                    verification.far.disparity(2)] == 0);
  verification.size_ok = isequal(verification.stereo, [600, 200]);
  verification.octave = version();
  fprintf("%s\n", jsonencode(verification));
  if ~(verification.centre_x_zero && verification.near_x_positive && ...
       verification.far_x_negative && verification.vertical_zero && ...
       verification.size_ok)
    error("stereo verification failed");
  endif
endfunction

function point = centroid(image, colour)
  matches = all(image == reshape(uint8(colour), 1, 1, []), 3);
  [rows, columns] = find(matches);
  point = mean([columns, rows], 1);
endfunction
