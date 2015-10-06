%  Copyright 2014(c) Analog Devices, Inc.
%
%  All rights reserved.
%
%  Redistribution and use in source and binary forms, with or without modification,
%  are permitted provided that the following conditions are met:
%      - Redistributions of source code must retain the above copyright
%        notice, this list of conditions and the following disclaimer.
%      - Redistributions in binary form must reproduce the above copyright
%        notice, this list of conditions and the following disclaimer in
%        the documentation and/or other materials provided with the
%        distribution.
%      - Neither the name of Analog Devices, Inc. nor the names of its
%        contributors may be used to endorse or promote products derived
%        from this software without specific prior written permission.
%      - The use of this software may or may not infringe the patent rights
%        of one or more patent holders.  This license does not release you
%        from the requirement that you obtain separate licenses from these
%        patent holders to use this software.
%      - Use of the software either in source or binary form or filter designs
%        resulting from the use of this software, must be connected to, run
%        on or loaded to an Analog Devices Inc. component.
%
%  THIS SOFTWARE IS PROVIDED BY ANALOG DEVICES "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
%  INCLUDING, BUT NOT LIMITED TO, NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A
%  PARTICULAR PURPOSE ARE DISCLAIMED.
%
%  IN NO EVENT SHALL ANALOG DEVICES BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
%  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, INTELLECTUAL PROPERTY
%  RIGHTS, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
%  BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
%  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
%  THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

% Inputs (structure containing the following fields)
% ============================================
% data_rate  = Output sample data rate (in Hz)
% FIR_interp = FIR decimation factor
% HB_interp  = half band filters decimation factor
% PLL_mult   = PLL multiplication
% Fpass      = passband frequency (in Hz)
% Fstop      = stopband frequency (in Hz)
% dBripple   = max ripple allowed in passband (in dB)
% dBstop     = min attenuation in stopband (in dB)
% dBstop_FIR = min rejection that TFIR is required to have (in dB)
% phEQ       = Phase Equalization on (not -1)/off (-1)
% int_FIR    = Use AD9361 FIR on (1)/off (0)
% wnom       = analog cutoff frequency (in Hz)
% converter_rate = converter (DAC/ADC) sampling rate (in Hz)
% clkPLL     = PLL frequency (in HZ)
%
% Outputs (structure containing the following fields)
% ===============================================
% rfirtaps         = fixed point coefficients for PROG RX FIR
% rxFilters        = system object for visualization (does not include analog filters)
% dBripple_actual  = actual passband ripple
% dBstop_actual    = actual stopband attentuation
% delay            = actual delay used in phase equalization
% webinar          = initialization for SimRF FMCOMMS2 Rx model

function result = internal_designrxfilters9361_sinc(input)

if ~input.wnom
    wc = (input.clkPLL/input.caldiv)*(log(2)/(2*pi));
else
    wc = input.wnom;
end

wTIA = wc*(2.5/1.4);

% Define the analog filters (for design purpose)
[b1,a1] = butter(1,2*pi*wTIA,'s');  % 1st order
[b2,a2] = butter(3,2*pi*wc,'s');    % 3rd order

% Digital representation of the analog filters (It is an approximation for group delay calculation only)
[z1,p1,k1] = butter(3,coerce_cutoff(wc/(input.converter_rate/2)),'low');
[sos1,g1] = zp2sos(z1,p1,k1);
Hd1=dsp.BiquadFilter('SOSMatrix',sos1,'ScaleValues',g1);
[z2,p2,k2] = butter(1,coerce_cutoff(wTIA/(input.converter_rate/2)),'low');
[sos2,g2] = zp2sos(z2,p2,k2);
Hd2=dsp.BiquadFilter('SOSMatrix',sos2,'ScaleValues',g2);
Hanalog = cascade(Hd2,Hd1);

% Define the digital filters with fixed coefficients
hb1 = 2^(-11)*[-8 0 42 0 -147 0 619 1013 619 0 -147 0 42 0 -8];
hb2 = 2^(-8)*[-9 0 73 128 73 0 -9];
hb3 = 2^(-4)*[1 4 6 4 1];
dec3 = 2^(-14)*[55 83 0 -393 -580 0 1914 4041 5120 4041 1914 0 -580 -393 0 83 55];

Hm1 = dsp.FIRDecimator(2, hb1);
Hm2 = dsp.FIRDecimator(2, hb2);
Hm3 = dsp.FIRDecimator(2, hb3);
Hm4 = dsp.FIRDecimator(3, dec3);

hb1 = input.HB1;
hb2 = input.HB2;
if input.HB3 == 2
    hb3 = 2;
    dec3 = 1;
elseif input.HB3 == 3
    hb3 = 1;
    dec3 = 3;
else
    hb3=1;
    dec3=1;
end

% convert the enables into a string
enables = strrep(num2str([hb1 hb2 hb3 dec3]), ' ', '');
switch enables
    case '1111' % only RFIR
        Filter1 = 1;
    case '2111' % Hb1
        Filter1 = Hm1;
    case '1211' % Hb2
        Filter1 = Hm1;
    case '1121' % Hb3
        Filter1 = Hm1;
    case '2211' % Hb2,Hb1
        Filter1 = cascade(Hm2,Hm1);
    case '2121' % Hb3,Hb1
        Filter1 = cascade(Hm3,Hm1);
    case '2221' % Hb3,Hb2,Hb1
        Filter1 = cascade(Hm3,Hm2,Hm1);
    case '1113' % Dec3
        Filter1 = Hm4;
    case '2113' % Dec3,Hb1
        Filter1 = cascade(Hm4,Hm1);
    case '2213' % Dec3,Hb2,Hb1
        Filter1 = cascade(Hm4,Hm2,Hm1);
    case '1221' % Hb3,Hb2
        Filter1 = cascade(Hm3,Hm2);
    case '1213' % Dec3,Hb2
        Filter1 = cascade(Hm4,Hm2);
    otherwise
        error('ddcresponse:IllegalOption', 'At least one of the stages must be there.')
end

Hmiddle=Filter1;

% Find out the best fit delay on passband
Nw = 2048;
w = zeros(1,Nw);
phi = zeros(1,Nw);
invariance = zeros(1,Nw);

w(1) = -input.Fpass;
for i = 2:(Nw)
    w(i) = w(1)-2*w(1)*i/(Nw);
end

response = analogresp('Rx',w,input.converter_rate,b1,a1,b2,a2).*freqz(Filter1,w,input.converter_rate);
for i = 1:(Nw)
    invariance(i) = real(response(i))^2+imag(response(i))^2;
end

phi(1)=atan2(imag(response(1)),real(response(1)));
for i = 2:(Nw)
    phi(i) = phi(i-1)+alias_b(atan2(imag(response(i)),real(response(i)))-phi(i-1),2*pi);
end

sigma = sum(invariance);
sigmax = sum(w.*invariance);
sigmay = sum(phi.*invariance);
sigmaxx = sum(w.*w.*invariance);
sigmaxy = sum(w.*phi.*invariance);
delta = sigma*sigmaxx-sigmax^2;
b = (sigma*sigmaxy-sigmax*sigmay)/delta;
if input.phEQ == 0 || input.phEQ == -1
    delay = -b/(2*pi);
else
    delay = input.phEQ*(1e-9);
end

% Design the PROG RX FIR
G = 16384;
clkRFIR = input.data_rate*input.FIR_interp;
Gpass = floor(G*input.Fpass/clkRFIR);
Gstop=ceil(G*input.Fstop/clkRFIR);
Gpass = min(Gpass,Gstop-1);
fg = zeros(1,Gpass);
omega = zeros(1,Gpass);

% pass band
for i = 1:(Gpass+1)
    fg(i) = (i-1)/G;
    omega(i) = fg(i)*clkRFIR;
end
rg1 = analogresp('Rx',omega,input.converter_rate,b1,a1,b2,a2).*freqz(Filter1,omega,input.converter_rate);
phase = unwrap(angle(rg1));
gd1 = GroupDelay(omega,phase); % group delay on passband for Analog + Converter + HB
omega1 = omega;                % frequency grid on pass band
rg2 = exp(-1i*2*pi*omega*delay);
rg = rg2./rg1;
w = abs(rg1)/(dBinv(input.dBripple/2)-1);

g = Gpass+1;
% stop band
for m = Gstop:(G/2)
    g = g+1;
    fg(g) = m/G;
    omega(g) = fg(g)*clkRFIR;
    rg(g) = 0;
end
wg1 = abs(analogresp('Rx',omega(Gpass+2:end),input.converter_rate,b1,a1,b2,a2).*freqz(Filter1,omega(Gpass+2:end),input.converter_rate));
wg2 = (wg1)/(dBinv(-input.dBstop));
wg3 = dBinv(input.dBstop_FIR);
wg = max(wg2,wg3);
grid = fg;
if input.phEQ == -1
    resp = abs(rg);
else resp = rg;
end
weight = [w wg];
weight = weight/max(weight);

% design RFIR filter
cr = real(resp);
B = 2;
F1 = grid(1:Gpass+1)*2;
F2 = grid(Gpass+2:end)*2;
A1 = cr(1:Gpass+1);
A2 = cr(Gpass+2:end);
W1 = weight(1:Gpass+1);
W2 = weight(Gpass+2:end);

% Determine the number of taps for RFIR
if hb3 == 1
    N = min(16*floor(input.converter_rate/(input.data_rate)),128);
else
    N = min(16*floor(input.converter_rate/(2*input.data_rate)),128);
end
tap_store = zeros(N/16,N);
dBripple_actual_vector = zeros(N/16,1);
dBstop_actual_vector = zeros(N/16,1);
i = 1;

while (1)
    if input.int_FIR
        d = fdesign.arbmag('N,B,F,A',N-1,B,F1,A1,F2,A2);
    else
        d = fdesign.arbmag('B,F,A,R');
        d.NBands = 2;
        d.B1Frequencies = F1;
        d.B1Amplitudes = A1;
        d.B1Ripple = db2mag(-input.dBstop);
        d.B2Frequencies = F2;
        d.B2Amplitudes = A2;
        d.B2Ripple = db2mag(-input.dBstop);
    end
    Hd = design(d,'equiripple','B1Weights',W1,'B2Weights',W2,'SystemObject',false);
    ccoef = Hd.Numerator;
    M = length(ccoef);
    
    if input.phEQ ~= -1
        sg = 0.5-grid(end:-1:1);
        sr = imag(resp(end:-1:1));
        sw = weight(end:-1:1);
        F3 = sg(1:G/2-Gstop+1)*2;
        F4 = sg(G/2-Gstop+2:end)*2;
        A3 = sr(1:G/2-Gstop+1);
        A4 = sr(G/2-Gstop+2:end);
        W3 = sw(1:G/2-Gstop+1);
        W4 = sw(G/2-Gstop+2:end);
        if input.int_FIR
            d2 = fdesign.arbmag('N,B,F,A',N-1,B,F3,A3,F4,A4);
        else
            d2 = fdesign.arbmag('N,B,F,A',M-1,B,F3,A3,F4,A4);
        end
        Hd2 = design(d2,'equiripple','B1Weights',W3,'B2Weights',W4,'SystemObject',false);
        scoef = Hd2.Numerator;
        for k = 1:length(scoef)
            scoef(k) = -scoef(k)*(-1)^(k-1);
        end
    else
        scoef = 0;
    end
    tap_store(i,1:M)=ccoef+scoef;
    
    Hmd = dsp.FIRDecimator(input.FIR_interp,tap_store(i,1:M));
    if ~isempty(ver('fixedpoint'))
        Hmd.Numerator = double(fi(Hmd.Numerator,true,16));
    end
    
    addStage(Filter1,Hmd);
    
    % quantitative values about actual passband and stopband
    rg_pass = abs(analogresp('Rx',omega(1:Gpass+1),input.converter_rate,b1,a1,b2,a2).*freqz(Filter1,omega(1:Gpass+1),input.converter_rate));
    rg_stop = abs(analogresp('Rx',omega(Gpass+2:end),input.converter_rate,b1,a1,b2,a2).*freqz(Filter1,omega(Gpass+2:end),input.converter_rate));
    dBripple_actual_vector(i) = mag2db(max(rg_pass))-mag2db(min(rg_pass));
    dBstop_actual_vector(i) = -mag2db(max(rg_stop));
    
    if input.int_FIR == 0
        h = tap_store(1,1:M);
        dBripple_actual = dBripple_actual_vector(1);
        dBstop_actual = dBstop_actual_vector(1);
        removeStage(Filter1);
        break
    elseif dBripple_actual_vector(1) > input.dBripple || dBstop_actual_vector(1) < input.dBstop
        h = tap_store(1,1:N);
        dBripple_actual = dBripple_actual_vector(1);
        dBstop_actual = dBstop_actual_vector(1);
        removeStage(Filter1);
        break
    elseif dBripple_actual_vector(i) > input.dBripple || dBstop_actual_vector(i) < input.dBstop
        h = tap_store(i-1,1:N+16);
        dBripple_actual = dBripple_actual_vector(i-1);
        dBstop_actual = dBstop_actual_vector(i-1);
        removeStage(Filter1);
        break
    else
        N = N-16;
        i = i+1;
        removeStage(Filter1);
    end
end

Hmd = dsp.FIRDecimator(input.FIR_interp,h);
if ~isempty(ver('fixedpoint'))
    Hmd.Numerator = double(fi(Hmd.Numerator,true,16));
end
addStage(Filter1,Hmd);
rxFilters=Filter1;
gd2 = grpdelay(Hmd,omega1,clkRFIR).*(1/clkRFIR);
if input.phEQ == -1
    groupdelay = gd1 + gd2;
else
    groupdelay = gd1 + gd2';
end
grpdelayvar = max(groupdelay)-min(groupdelay);

aTFIR = 1 + ceil(log2(max(Hmd.Numerator)));
switch aTFIR
    case 2
        gain = +6;
    case 1
        gain = 0;
    case 0
        gain = -6;
    otherwise
        gain = -12;
end
if aTFIR > 2
    gain = +6;
end
bTFIR = 16 - aTFIR;
rfirtaps = Hmd.Numerator.*(2^bTFIR);

if length(rfirtaps) < 128
    rfirtaps = [rfirtaps,zeros(1,128-length(rfirtaps))];
end

webinar.Fout = input.data_rate;
webinar.FIR_interp = input.FIR_interp;
webinar.HB_interp = input.HB_interp;
webinar.PLL_mult = input.PLL_mult;
webinar.Fpass = input.Fpass;
webinar.Fstop = input.Fstop;
webinar.dBripple = input.dBripple;
webinar.dBstop = input.dBstop;
webinar.dBstop_FIR = input.dBstop_FIR;
webinar.phEQ = input.phEQ;
webinar.int_FIR = input.int_FIR;
webinar.wnom = input.wnom;
webinar.Hm1_rx = Hm1;
webinar.Hm2_rx = Hm2;
webinar.Hm3_rx = Hm3;
webinar.Hm4_rx = Hm4;
webinar.Hmd_rx = Hmd;
webinar.enable_rx = enables;

tohw.RXSAMP = input.data_rate;
tohw.RF = input.data_rate * input.FIR_interp;
tohw.R1 = tohw.RF * input.HB1;
tohw.R2 = tohw.R1 * input.HB2;
tohw.ADC = input.converter_rate;
tohw.BBPLL = input.clkPLL;
tohw.Coefficient = rfirtaps;
tohw.CoefficientSize = length(h);
tohw.Decimation = input.FIR_interp;
tohw.Gain = gain;
tohw.RFBandwidth = input.RFbw;

result.rfirtaps = rfirtaps;
result.taps_length = length(h);
result.rxFilters = rxFilters;
result.Hanalog = Hanalog;
result.Hd1 = Hd1;
result.Hd2 = Hd2;
result.Hmd = Hmd;
result.Hmiddle = Hmiddle;
result.dBripple_actual = dBripple_actual;
result.dBstop_actual = dBstop_actual;
result.delay = delay;
result.grpdelayvar = grpdelayvar;
result.webinar = webinar;
result.tohw = tohw;
result.b1 = b1;
result.a1 = a1;
result.b2 = b2;
result.a2 = a2;