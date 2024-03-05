function timing_fit(results_directory)

% arrow_files = dir([results_directory '*.arrow']);
json_files = dir([results_directory '*.json']);

csv_file = dir([results_directory '*.csv']);
schedule_file = json_files(~contains({json_files.name},'experiment'));
% events_file = arrow_files(contains({arrow_files.name},'events'));

S = readstruct([results_directory schedule_file.name]);
x  = cellfun(@(x) x(1),S.each)';
iMax = length(x);
jMax = S.step.step(2).each.length;
n = S.step.step(2).step.to/S.step.step(2).step.step;
dT = S.step.step(2).step.step;
nPerStream = (jMax*n);

[data, species] = load_csv([results_directory csv_file.name],'proteins');
indx = cellfun(@(x) contains(x,'state')&~contains(x,'timer'),species);
species_list = species(indx);
data = data(:,indx);

if (nPerStream)*iMax~=size(data,1)
    error('incompatible CSV and schedule')
end

out = nan(jMax,iMax);
for i = 1:iMax
    indx = (i-1)*nPerStream+1:i*nPerStream;
    tmp_data = data(indx,:);
    r_data = reshape(tmp_data(1:end,:),n,jMax,length(species_list));
    [~, indices] = max(r_data>200, [], 1);
    indices(all(r_data <= 200, 1)) = inf;
    tmp1 = squeeze(indices);
    tmp2 = [min(tmp1(:,1:2),[],2)-min(tmp1(:,[3 6]),[],2) min(tmp1(:,4:5),[],2)-min(tmp1(:,[3 6]),[],2)];
    out(:,i) = min(tmp2,[],2);
end

y = out*dT;
y(isinf(y)) = nan;
my = median(y,'omitmissing');

ft = fittype( 'power1');
opts = fitoptions( 'Method', 'NonlinearLeastSquares' );
opts.Display = 'Off';
opts.StartPoint = [3.95693420439204e-05 -1.0307694349438];

fitresult = fit(my',x, ft, opts );
sprintf('y = %f*x^(%f)',fitresult.a,fitresult.b)
end

function [data, species_out, t] = load_csv(file,types)
    table1 = readtable(file);
    species = table1.Properties.VariableNames;
    indx = cellfun(@(x) contains(x,types),species);
    species(indx);
    data = table1.Variables;
    data = data(:,indx);
    [~, indx_names] = sort(species(indx));
    tmp = species(indx);
    species_out = tmp(indx_names);
    data = data(:,indx_names);
    data(table1.t==0,:)=[];
    t = table1.t(table1.t~=0);
end
