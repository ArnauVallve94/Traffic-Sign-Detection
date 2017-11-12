%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                                                         %
%                       Master In Computer Vision                         %
%               M1 Introduction to Human and Computer Vision              %
%                               Project                                   %
%                                                                         %
% STUDENTS:                                                               %
%   Arnau Vallve                                                          %
%   Guillermo Torres                                                      %
%   Yevgeniy Kadranov                                                     %
%   Santiago Barbarisi                                                    %
%                                                                         %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% INPUT:
%       pathToDir           = the Path to get to the training folder, where 
%                             the images, anotations and ground truth are 
%                             stored.
%       ImagesName          = The name of all the images that are on the
%                             validation split.
%       model               = the model to be used to create the masks
%       regionModel         = the model to be used to find the bounding
%                             boxes over a mask image
%       tmpMatch            = boolean to apply template matching to the
%                             mask image
% 
% OUTPUT:
%       ValidationMasks     = A multidimensional matrix that has every mask
%                             from the validation set.
%       BoundingBoxes       = The list of boxes found for each image
%
%   This function get the mask for all the validation images that where
%   splited on the splitData function.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [ValidationMasks,BoundingBoxes] = maskGeneratorMM(pathToDir,ImagesName,model,regionModel,shapeModel)

    path = pathToDir;

    % Thresholds for HSV colorspace
    red = [15 320];
    blue = [195 240];
    sat = 0.5;
    val = [0.05 0.95];
    
    % Structural Elements for morphological filtering
    sm = strel('square',2);
    bm = strel('square',13);
    
    ValidationMasks = zeros(size(imread([path ImagesName{1}])));
    
    time = 0;
    switch model
        case 'HSV'
            % Method 1
            tic;
            for i = 1:length(ImagesName)
                image = imread([path ImagesName{i}]);
                % Image color space transformation from RGB to HSV
                imageHSV   = rgb2hsv(image);
                imageHSV(:,:,1) = imageHSV(:,:,1)*360;
                % Image filtering
                maskimage =  ((imageHSV(:,:,1)>=blue(1) & imageHSV(:,:,1)<=blue(2)) ...
                                | (imageHSV(:,:,1)>=red(2) | imageHSV(:,:,1)<=red(1))) ...
                                & (imageHSV(:,:,2)>=sat) ...
                                & (imageHSV(:,:,3)>=val(1) & imageHSV(:,:,3)<=val(2));
                
                % Apply Morphological filtering over the mask
                ValidationMasks(:,:,i) = imfill(imclose(imopen(maskimage,sm),bm),'holes');
                % Apply region model to find bounding boxes
                BoundingBoxes(i,1) = RegionModel(ValidationMasks(:,:,i),regionModel,shapeModel);
                % Apply mask isolation so the only with pixels are within
                % every box on the mask
                ValidationMasks(:,:,i) = isolateBoxes(ValidationMasks(:,:,i),BoundingBoxes(i,1));
            end
            time = toc;
            
        case 'UCM'
            ths = 0.65;
            tic;
            for i = 1:length(ImagesName)
                % For Original method
                image = double(rgb2hsv(imread([path ImagesName{i}])));
                segImage = im2ucm(image,'fast');
                
                % For saved segmented images
%                 image = rgb2hsv(imread([path ImagesName{i}]));
%                 load(['segment-ucm/2/' ImagesName{i}(1:end-4) '.mat'])
%                 segImage = seg;
                segImage = segImage>=ths;
                labImage = gridbmap2seg(segImage);
                labels = unique(labImage(:))';
                
                finalUCMmask = zeros(size(labImage));
                finalUCMboxs = [];
                for j = labels
                    mask = double(labImage ==j);
                    if sum(mask(:))/(size(mask,1)*size(mask,2))>0.025 || sum(mask(:))/(size(mask,1)*size(mask,2))<0.0004
                        continue
                    end
                    
                    filtImage = image.*repmat(mask,1,1,3);
                    filtImage(:,:,1) = filtImage(:,:,1)*360;
                    % Image filtering
                    mask =  ((filtImage(:,:,1)>=blue(1) & filtImage(:,:,1)<=blue(2)) ...
                                    | (filtImage(:,:,1)>=red(2) | filtImage(:,:,1)<=red(1))) ...
                                    & (filtImage(:,:,2)>=sat) ...
                                    & (filtImage(:,:,3)>=val(1) & filtImage(:,:,3)<=val(2));
                    
                    % Try to improve with extra color segmentation
                    boxes = RegionModel(mask,regionModel,shapeModel);
                    if ~isempty(boxes{1}(:,:))
                        finalUCMmask = finalUCMmask | isolateBoxes(mask,boxes);
                        finalUCMboxs = [finalUCMboxs;boxes{1}];
                    end
                end
                ValidationMasks(:,:,i) = finalUCMmask;
                BoundingBoxes(i,1) = {finalUCMboxs};
            end
            time = toc;
    end
    fprintf('The mean time for processing the images is: %.3f \n',time/length(ImagesName))

end

function boxes = RegionModel(toFilter,regionModel,shapeModel)
    mask = toFilter;
    switch regionModel
        % Conected Components Labeling method
        case 'CCL'
            % Calling the BBox  function with signal parameters calculated in week1
            
            boxes{1,1}= BBoxDetect(mask);
        
        case 'Global'
        % Global method to apply sliding window with template matching
            scaleFact = 0.2;
            tmpShapes = {'circle','square','triangle','inverted triangle'};
            tmpSize = 35;
            ths = 0.40;
            FBox = [];
            step = 20;
            index = 1;
            while scaleFact <= 1

                [ni,nj] = deal(round(size(mask,1)*scaleFact),round(size(mask,2)*scaleFact));
                im = imresize(mask, [ni, nj], 'Nearest');
                
                % Global method with Connected Components Labels
                % Detecting connected components (default connectivity of 4)
                Concomp = bwconncomp(im,4); 

                % Extracting bounding boxes from the connected components
                BBox=regionprops(Concomp,'BoundingBox'); 
                
                for i=1:length(BBox)
                    % Rounding positions of bounding box
                    pos=round(BBox(i).BoundingBox);

                    % Cropping the region wihtin the bounding box
                    box = im(pos(2):pos(2)+pos(4)-1,pos(1):pos(1)+pos(3)-1);
                    
                    if pos(3)*pos(4)<=900*scaleFact
                        continue
                    end
                    
                    for j = 1:numel(tmpShapes)
                        tmp = createTemplate(tmpShapes{j},[pos(4) pos(3)]);
                        xc = corr2(tmp,box);

                        % Setting conditions for signals
                        if xc>=ths
                            % If the condition is satisfied adding Bounding box to the vector
                            bb=BBox(i).BoundingBox./scaleFact;
                            
                            FBox(index,:) = [bb(1:2) ...
                                min(bb(1)+bb(3),nj/scaleFact)-bb(1)-1 ...
                                min(bb(2)+bb(4),ni/scaleFact)-bb(2)-1];
                            
                            index = index+1;
                        end
                    end
                end
                
                % Global method with Sliding Window
%                 for i = 1:numel(tmpShapes)
%                     tmp = createTemplate(tmpShapes{i},tmpSize);
% 
%                     
%                     for n = 1:step:ni-tmpSize
%                         for m = 1:step:nj-tmpSize
%                             box = im(n:n+tmpSize-1,m:m+tmpSize-1);
%                             xc = corr2(tmp,box);
%                             if xc>=ths
%                                 window = [m,n,tmpSize,tmpSize];
%                                 FBox(index,:) = window./scaleFact;
%                                 index = index+1;
%                             end
%                         end
%                     end
%                 end
                
                scaleFact = scaleFact+0.1;
            end
            
            if ~isempty(FBox)
%                 FBox = unique(FBox,'rows');
                boxes{1,1} = filterBoxes(FBox,[size(mask,1) size(mask,2)]);
            else
                boxes{1,1} = [];
            end
            
        otherwise
            % Thre methods: Sliding Window, Integral Image and Convolution
            % where the difference relys on the way that the mask area is
            % calculated.
            
            % Matrix initialization for bounding boxes
            FBox = [];
            index = 1;
            % Scaling factor to resize the masks
            scaleFact = 0.1;
            % Size of the sliding window
            h = 35;
            w = 35;
            windowArea = h*w;
            % Step for the window iteration
            step = 20;
            % Threshold to satisfy
            ths = [0.55 0.95];
            while scaleFact <= 1
                % Size of the resized image
                [ni,nj] = deal(round(size(mask,1)*scaleFact),round(size(mask,2)*scaleFact));
                % Apply change of size
                im = imresize(mask, [ni, nj], 'Nearest');
                
                % Apply if necesary to improve computation speed
                switch regionModel
                    case 'Integral Image'
                        im = cumsum(cumsum(im),2);
                    case 'Convolution'
                        convEl = ones(h,w);
                        im = conv2(im,convEl,'same');
                end
                % Iterate over the mask
                for n = 1:step:ni-h
                    for m = 1:step:nj-w
                        maskArea = 0;
                        % Calculate mask area
                        switch regionModel
                            case 'Sliding Window'
                                box = im(n:n+h-1,m:m+w-1);
                                maskArea = sum(box(:));
                            case 'Integral Image'
                                if m==1 && n==1
                                    maskArea = im(n+h-1,m+w-1);
                                elseif n==1
                                    maskArea = im(n+h-1,m+w-1) - im(n+h-1,m-1);
                                elseif m==1
                                    maskArea = im(n+h-1,m+w-1) - im(n-1,m+w-1);
                                else
                                    maskArea = im(n+h-1,m+w-1) - im(n+h-1,m-1) - im(n-1,m+w-1) + im(n-1,m-1);
                                end
                            case 'Convolution'
                                maskArea=im(n + ceil((h - 1) / 2) - 1,m + ceil((w - 1) / 2) - 1);
                        end
                        % Check threshold condition
                        if maskArea/windowArea>=ths(1) && maskArea/windowArea<=ths(2);
                            window = [m,n,w,h];
                            FBox(index,:) = window./scaleFact;
                            index = index+1;
                        end
                    end
                end
                % Update scaling factor
                scaleFact = scaleFact+0.1;
            end
            % If boxes where founded then find the most prominent ones
            if ~isempty(FBox)
                boxes{1,1} = filterBoxes(FBox,[size(mask,1) size(mask,2)]);
            else
                boxes{1,1} = [];
            end
    end
    
    
    % If else to apply shape modeling: if it is Hough it enters to the if,
    % else it check if the regionModel was not Global and at least found
    % one box
    if strcmp(shapeModel,'Hough') && ~isempty(boxes{1}(:,:))% && ~strcmp(regionModel,'Global')
        finalboxes = [];
        mask = toFilter;
        index=1;
        boxesMat = boxes{1};
        for i=1:size(boxesMat,1)
            box = round(boxesMat(i,:));
            Icrop = mask(box(2):box(2)+box(4)-1,box(1):box(1)+box(3)-1);
            %line hough
            isSign = HoughBbox(padarray(Icrop,[1,1])); % padarray is to detect extereme lines (on the edge)

            %circle hough
            isSignCM = CircleHoughBboxM(padarray(Icrop,[1,1]));

            %put if 2 either coond is met the box to a new cell
            if (isSign == 1 || isSignCM == 1)
                finalboxes(index,:)=box; % if the condition is satisfied adding Bounding box to the cell
                index = index+1;
            end

        end
    
    elseif ~strcmp(regionModel,'Global') && ~isempty(boxes{1}(:,:))
        finalboxes = [];
        mask = toFilter;
        % Template shapes
        tmpShapes = {'circle','square','triangle','inverted triangle'};
        % Get detected boxes
        boxesMat = boxes{1};
        index = 1;
        
        switch shapeModel
            % Correlation as a classification method
            case 'Correlation'
                % Threshold value
                ths = 0.5;
                % Iterate over the boxes founded
                for i = 1:size(boxesMat,1)
                    box = round(boxesMat(i,:));
                    ts = [box(:,4) box(:,3)];
                    % We only use the content of the mask within the
                    % bounding box
                    msk = mask(box(2):box(2)+box(4)-1,box(1):box(1)+box(3)-1);
                    for j = 1:numel(tmpShapes);
                        % Create template
                        tmp = createTemplate(tmpShapes{j},ts);
                        
                        % CHOOSE one uncommenting it and commenting the
                        % other
                        
                        % Rotation of the template
%                         for k = 1:5
%                             vec = [-10 -5 0 5 10];
%                             tmpr = imrotate(tmp,vec(k),'crop');
%                             vals(k) = corr2(tmpr,msk);
%                         end
%                         corrVals(j) = max(vals)>=ths;

                        % No rotation of the template
                        corrVals(j) = corr2(tmp,msk);
                    end
                    % Check if threshold was satisfied
                    if max(corrVals)>=ths
                        [~,idx] = sort(corrVals,'descend');
                        
                        if ~(corrVals(idx(1))-corrVals(idx(2))>0.3)
                            finalboxes(index,:) = box;
                            index = index + 1;
                        end
                    end
                end
            % Distance as a classification method
            case 'Distance Transform'
                % Threshold value
                ths = 200;
                for i = 1:size(boxesMat,1)
                    box = round(boxesMat(i,:));
                    ts = [box(:,4) box(:,3)];
                    msk = mask(box(2):box(2)+box(4)-1,box(1):box(1)+box(3)-1);
                    % Apply either edge detection or not with the distance
                    % transform
                    msk = bwdist(edge(msk,'Sobel'));
                    for j = 1:numel(tmpShapes);
                        % Create template
                        tmp = createTemplate(tmpShapes{j},ts);
                        
                        % CHOOSE one uncommenting it and commenting the
                        % other
                        
                        % With Rotation
%                         for k = 1:5
%                             vec = [-10 -5 0 5 10];
%                             tmpr = imrotate(tmp,vec(k),'crop');
%                             tmpr = edge(tmpr,'Sobel');
%                             cv(k) = sum(sum(msk.*tmp));
%                         end
%                         distVals(j) = min(cv);
                        
                        % Without Rotation
                        tmp = edge(tmp,'Sobel');
                        distVals(j) = sum(sum(msk.*tmp));
                    end
                    % Check if threshold was satisfied and keep bounding
                    % box if true
                    if min(distVals)>ths
                        finalboxes(index,:) = box;
                        index = index + 1;
                    end
                end
                
        end
        % return bounding boxes or empty box if not founded
    end
    
    if exist('finalboxes','var')
        if ~isempty(finalboxes)
            boxes{1,1} = finalboxes;
        else
            boxes{1,1} = [];
        end
    end
    
end

function [isSign] = HoughBbox(Icrop)
    isSign=0;
    BW=edge(Icrop,'canny');
    [H,T,R]=hough(BW);

    P = houghpeaks(H,5,'threshold',ceil(0.3*max(H(:))),'NHoodSize',2*floor(size(H)/15/2)+1);

    lines = houghlines(BW,T,R,P,'FillGap',15,'MinLength',7);

    countHori=0; %count horizontal lines for square/triangle
    countVert=0; %count vertical lines for square
    countDiaP=0; %count positive diagonals for triangle
    countDiaN=0; %count negative diagonals for triangle
    vertThresh=15;
    horThresh=75;
    diagUpPos=43;
    diagLoPos=18;
    diagUpNeg=-18;
    diagLoNeg=-43;
    for k = 1:length(lines)
        %if (lines(k).theta)==-1
        %count lines in every needed direction for square and triangle detection
        if abs(lines(k).theta) <= vertThresh
            countVert = countVert + 1;
        end
        if abs(lines(k).theta) >= horThresh
            countHori = countHori + 1;
        end
        if lines(k).theta >= diagLoNeg && lines(k).theta <= diagUpNeg
            countDiaN = countDiaN+1;
        end
        if lines(k).theta <= diagUpPos && lines(k).theta >= diagLoPos
            countDiaP = countDiaP+1;
        end
    end
    if (countHori>=2 && countVert>=2) || (countHori>=1 && countDiaP>=1 && countDiaN>=1)

        isSign=1;

    end
end

function [isSignCM] = CircleHoughBboxM(Icrop)
    Icrop = edge(Icrop,'Canny');
    xrad_min = round(min(size(Icrop))/2.7);
    xrad_max = round(min(size(Icrop))/1.7);
    isSignCM = 0;
    edThs = 0.2;
    sns = 0.95;

    [centers,~] = imfindcircles(Icrop,[xrad_min xrad_max],'ObjectPolarity','bright','EdgeThreshold',edThs,'Sensitivity',sns);
    if numel(centers) > 0
        isSignCM = 1;
    end
end

function tmp = createTemplate(shape,sz)
    % The function creates a template with 'shape' and size 'sz'
    
    % It can take only 1 value or 2
    if size(sz,2)==1
        sz = [sz sz];
    end
    
    % Create a smaller template
    rsz = round(sz*0.85);
    
    % Get difference
    mrg = sz - rsz;
    
    switch shape
        case 'circle'
            if rsz(1)==rsz(2)
                ax = linspace(-rsz(1)/2+1,rsz(1)/2-1,rsz(1));
                [x,y] = meshgrid(ax,ax);
                tmp = x.^2 + y.^2 <= (rsz(1)/2)^2;
            else
                [mval,in] = min(rsz);
                ax = linspace(-mval/2+1,mval/2-1,mval);
                [x,y] = meshgrid(ax,ax);
                tmp = double(x.^2 + y.^2 <= (mval/2)^2);
                if rsz(in) == rsz(1)
                    tmp = [zeros(rsz(in),floor((rsz(2)-rsz(1))/2)) tmp zeros(rsz(in),ceil((rsz(2)-rsz(1))/2))];
                elseif rsz(in) == rsz(2)
                    tmp = [zeros(floor((rsz(1)-rsz(2))/2),rsz(in)); tmp; zeros(ceil((rsz(1)-rsz(2))/2),rsz(in))];
                end

            end
        case 'square'
            tmp = ones(rsz);
            
        otherwise
            zmat = zeros(rsz);
            rst = 1;

            for i = rsz(1):-1:1
                zmat(i,round(rst)+1:end-round(rst)+1) = 1;
                rst = rst + rsz(2)/rsz(1)/2;
            end
            
            switch shape
                case 'triangle'
                    tmp = zmat;

                case 'inverted triangle'
                    tmp = zmat(end:-1:1,end:-1:1);
            end
            
    end
    % Center the template tmp in a bigger image
    mat = zeros(sz);
    mrg = round(mrg./2);
    mat(mrg(1):mrg(1)+rsz(1)-1,mrg(2):mrg(2)+rsz(2)-1) = tmp;
    tmp = mat;

end

function FinalBBox = BBoxDetect(im)
    % Features to be satisfy by bounding boxes with CCL
    [MinSize,MaxSize,FRmin,FRmax,FFmin,FFmax] = deal(900,52000,0.5,0.95,0.6,1.2);

    % Detecting connected components (default connectivity of 4)
    Concomp = bwconncomp(im,4); 
    
    % Extracting bounding boxes from the connected components
    BBox=regionprops(Concomp,'BoundingBox'); 
 
    % Initialise number of filtered detection (amount of accepted Bboxes in the same image)    
    j=1;
    
    % In case there are no boxes
    FinalBBox = []; 
    
    % Looping over each box detected
    for i=1:length(BBox)
        % Rounding positions of bounding box
        pos=round(BBox(i).BoundingBox);
        
        % Cropping the region wihtin the bounding box
        box=imcrop(im,[pos]);
        
        % Calculating area of non-zero pixels
        maskArea=sum(box(:));
        
        % Calculating area of the Bbox
        BBoxArea=BBox(i).BoundingBox(3)*BBox(i).BoundingBox(4);
        
        % Calculating filling ration
        fillRatio=maskArea./BBoxArea;
        
        % Calculating Form Factor
        formFactor= BBox(i).BoundingBox(3)./BBox(i).BoundingBox(4);
        
        % Setting conditions for signals
        if BBoxArea>MinSize && BBoxArea<MaxSize && fillRatio>FRmin && fillRatio<=FRmax && formFactor<FFmax && formFactor>FFmin 
            %rectangle('Position',BBox(i).BoundingBox,'EdgeColor','r','LineWidth',2)
            % If the condition is satisfied adding Bounding box to the vector
            FinalBBox(j,:)=BBox(i).BoundingBox;
            j = j+1;
        end
    end
end

function Boxes = filterBoxes(FBox,sz)
    % As the 3 and 4 column gives the size of the box we want the center so its
    % the half of them
    toCenter = FBox(:,3:4)./2;

    % We add that to the upper left points and normalize [0,1]
    center = (FBox(:,1:2) + toCenter)./repmat([sz(2) sz(1)],size(FBox,1),1);
    
    % Number of boxes
    numBoxes = size(FBox,1);

    % Threshold to filter the centroid's neighbors
    threshold = 0.1;

    % Until the condition doesn't satisfy the threshold, will remain iterating
    condThreshold = 0.85;
    condition = false;

    % initialize the k means number of centroids
    k = 1;
    while ~condition
        % will contain the number of centroid's that are at a certain distance
        % to their centroid
        conTrue = 0;
        % The position of the elements that fullfill the condition
        posTrue = [];
        % Apply k means algorithm to the center of the boxes with k centroids
        [ind,Cent] = kmeans(center,k);
        for i = 1:k
            % Find the indexes from cluster k
            pos = find(ind==i);
            % Find the centers from cluster k
            centerValues = center(pos,:);
            % Calculate cluster's distance to its centroid
            neighbors = pdist2(Cent(i,:),centerValues);
            % Which of them are at least at a certain distance
            conCheck = find(neighbors<threshold);
            % Store the indexes that fullfill the radius condition
            posTrue = [posTrue;pos(conCheck)];
            % Number of elements within a cluster that fullfill the raduis
            % condition
            conTrue = conTrue + numel(conCheck);
        end
        if conTrue/numBoxes >= condThreshold
            condition = true;
        else
            k = k + 1;
        end
    end
    % Keep only boxes that satisfy the radious condition
    ind = ind(posTrue);
    FBox = FBox(posTrue,:);

    clusters = unique(ind);
    Boxes = [];
    % Create bounding box for each cluster with the most upper left point
    % and the lower right point
    for i=clusters'
        boxes = FBox(ind==i,:);
        boxes = [round(min(boxes(:,1:2),[],1)) round(max(boxes(:,3:4)+boxes(:,1:2)-1,[],1))];
        Boxes = [Boxes;boxes(:,1:2) boxes(:,3:4)-boxes(:,1:2)];
    end
end

function mask = isolateBoxes(image,boxes)
    % Keep only information within a box or keep the same if bounding box
    % not returned
    mask = zeros(size(image));
    
    if size(boxes,1)==0
        mask = image;
        return
    end
    
    for i = 1:size(boxes,1)
        box = boxes{i,:};
        for j = 1:size(box,1)
            bb = box(j,:);
            part = image(ceil(bb(2)):floor(bb(2)+bb(4))-1,ceil(bb(1)):floor(bb(1)+bb(3))-1);
            mask(ceil(bb(2)):floor(bb(2)+bb(4))-1,ceil(bb(1)):floor(bb(1)+bb(3))-1) = part;
        end
    end
end

