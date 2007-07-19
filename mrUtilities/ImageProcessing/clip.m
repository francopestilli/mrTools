function im = clip(im, cmin, cmax)
% clip(im, cmin, cmax)
%	Clips image values between cmin and cmax.
%	Default values for cmin and cmax based on image histogram.
%

if ieNotDefined('cmin') | ieNotDefined('cmax')
    imvec = im(:);
    histThresh = length(imvec)/1000;
    [cnt, val] = hist(imvec,100);
    goodVals = find(cnt>histThresh);
    clipMin = val(min(goodVals));
    clipMax = val(max(goodVals));
    cRange = [clipMin,clipMax];
end

if ~exist('cmin')
  cmin = cRange(1);
end
if ~exist('cmax')
  cmax = cRange(2);
end

im(im<cmin) = cmin;
im(im>cmax) = cmax;

return

