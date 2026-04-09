# Dynamic FFE Tap Toggling for Improved Power

In a SerDes receiver, a Feed-Forward Equalizer (FFE) is used to compensate for channel impairments. The FFE is composed of multiple taps, each tasked with cleaning the received signal, but also each consuming a significant amount of power. 

This project aims to identify and selectively disable insignificant taps during a 224Gbps SerDes system's initial adaptation, reducing overall power consumption during steady-state data transmission while maintaining acceptable signal integrity.

## Tap Toggling Algorithms

### Margin Lock – Proposed Algorithm

The goal of the proposed tap toggling algorithm, Margin Lock [`(MarginLock.m)`](/TapTogglingAlgos/MarginLock.m), is to disable as many FFE taps as possible without sacrificing signal integrity. For acceptable signal quality levels, the system must satisfy two constraints after the algorithm completes:
1. **Bit Error Rate (BER)** must remain below 1e-8.
2. **Channel Operating Margin (COM)**, evaluated at the target BER above, must remain above 3 dB.

Margin Lock uses a greedy approach: it disables one tap at a time, starting with the least significant ①, and checks whether both constraints still hold. Because FFE taps typically have long tails of small taps, the least significant taps tend to be the smallest in magnitude. If disabling a tap leaves the COM above 3 dB, the algorithm moves on to the next-smallest tap. If the COM drops below 3 dB, the algorithm re-enables that tap and terminates.

![Margin Lock Algorithm's Flow](/images/margin_lock_flow.svg)

Computing COM exactly requires either a detailed statistical analysis of the channel's impulse response or a measurement over hundreds of millions of symbols for the target BER. Margin Lock avoids both by estimating COM from a few thousand error samples taken between the DFE output and its slicer decision ②. Because residual intersymbol interference (ISI), crosstalk, noise, and jitter are in general normally distributed, the error samples are well-modeled by a Gaussian. Specifically, Margin Lock computes a running mean of the absolute error samples, which follow a half-normal distribution, and derives the underlying standard deviation ③. From that standard deviation it locates the distribution's tail and estimates the COM based on the target BER ④. If the estimate exceeds 3 dB, the algorithm proceeds to disable the next tap ①; otherwise, it re-enables the last disabled tap and terminates ⑤.

### Margin Lock's Convergence Time

Margin Lock determines whether to disable the next-smallest tap or terminate based on absolute error samples collected over 10 LMS iterations, which in our case correspond to 40,960 symbols. Since our model uses 31 FFE taps, one of which serves as the main cursor fixed to 1, and the first post-cursor tap is fixed at zero due to the DFE, a maximum of 29 taps can be disabled. Consequently, the algorithm can run for at most one million symbols, typically representing only a small fraction of the total adaptation time.

### Margin Lock’s Hardware Feasibility

The algorithm's hardware overhead is minimal. To keep the design simple, the median value of the absolute error samples is tracked instead of a complex running average. It only needs a single storage register to hold the current median estimate and a basic voting circuit to adjust it. To avoid significant computations, each new absolute error is compared to the current median. If the majority of errors are larger than the estimate, the hardware nudges the median value up by a small step. If the majority are smaller, it nudges the value down.

To approximate the COM, this median value is simply multiplied by a pre-computed scale factor that corresponds to the target BER. This voting system eliminates the need for heavy computations, making it an incredibly cost-effective and power-efficient way to monitor signal quality in real time.

### Other Evaluated Algorithms

Four other algorithms have been evaluated. The table below provides a brief description of each and its limitations.

| Algorithm | Description | Limitations |
| --------- | ----------- | ----------- |
| Informed Min Coefficient<br />_[`(InformedMinCoeff.m)`](/TapTogglingAlgos/InformedMinCoeff.m)_ | Sequentially turns off taps based on estimated error and the target BER | Does not sufficiently take into account the COM |
| Leveraged LMS<br />_[`(LeveragedLMS.m)`](/TapTogglingAlgos/LeveragedLMS.m)_ | Sequentially turns off taps based on the system’s measured error response | Detecting spikes in the error response relies on manually tuned parameters |
| Min Coefficient<br />_[`(MinCoeff.m)`](/TapTogglingAlgos/MinCoeff.m)_ | Turns off N smallest taps | Hand-tuning N across all channels is impractical and constrains it to a low value |
| Threshold<br />_[`(Threshold.m)`](/TapTogglingAlgos/Threshold.m)_ | Turns off all taps with magnitudes below a certain pre-set cutoff | Taps that initially appear small may significantly degrade signal quality if turned off |

## 224Gbps SerDes Model

The tap-toggling algorithm has been evaluated on a PAM4 224 Gbps SerDes model, extended from Mathworks’ [Architectural 112G PAM4 ADC-Based SerDes Model](https://www.mathworks.com/help/serdes/ug/architectural-112g-pam4-adc-based-serdes-model.html). The model consists of a Stimulus that generates a PRBS31 PAM4 sequence and sends it to the transmitter (TX). The TX then applies minimal equalization and sends the binary sequence across the channel. The receiver (RX) applies heavy equalization to clean the signal.

![High-Level SerDes Model Overview](/images/high_level_serdes_model.svg)

TX only uses a 4-tap Finite Impulse Response (FIR) filter with a Voltage Gain Amplifier (VGA) for pre-emphasis. The FIR taps are calculated in the TX’s initialization function.

![TX Block Overview](/images/tx_model.svg)

RX consists of two parts: an analog frontend (AFE) for initial equalization and a digital signal processing (DSP) block for further signal cleaning and outputting the PAM4 symbol decisions.

![RX Block Overview](/images/rx_model.svg)

AFE consists of three-stage Continuous Time Linear Equalizers (CTLEs) that apply a high-frequency boost to compensate for the channel's low-pass behaviour, flattening the overall frequency response. A VGA then scales the signal’s amplitude to match the ADCs’ range.

The AFE output is digitized by time-interleaved ADCs, where four 7-bit SAR ADCs with a 400 mV peak-to-peak range sample the signal on staggered clock phases to achieve the desired aggregate rate. The 64 parallel samples are then demuxed and handed off to the DSP for equalization and PAM4 slicing.

These parallel samples first pass through a Feed-Forward Equalizer (FFE) with 6 pre-cursor taps and 24 post-cursor taps, which removes the pre-cursor and post-cursor ISI. Finally, the samples pass through a 1-tap Decision Feedback Equalizer (DFE) that removes the post-cursor ISI based on the previous decision. Since DFE removes the post-cursor ISI, the first post-cursor tap in FFE is fixed to zero. The DFE also outputs the PAM4 symbol decisions based on the PAM4 data levels (dlevs).

The model uses the sign-sign Least Mean Squares (LMS) algorithm with an accumulation window of 64×64 = 4096 symbols for the first million symbols. It adjusts the FFE taps, the DFE tap, and the PAM4 dlevs over time to achieve an open eye.

For Clock Domain Recovery (CDR), the model employs a Mueller-Mueller phase detector with loop filter to drive the Voltage Controlled Oscillator (VCO) at the correct phase offset. To avoid spending a large chunk of simulation time locking the MMCDR, the model initializes the phase offset to a proper value based on the channel’s impulse response.

The tap toggling algorithm has access to the entire LMS block’s internal state and takes in DFE’s output samples and decisions as inputs to provide FFE with a bit mask indicating which taps should be turned on or off.

## Running the Model

After importing the repository as a MATLAB project, it is ready to be run for three million symbols on a Medium Reach channel and use Margin Lock to turn off taps.

To disable FFE tap toggling or select a different algorithm, navigate to RX > ADC_EQ, double-click the LMSUpdate block, and choose an algorithm from the list. Select 'base' to disable tap toggling.

![Selecting Tap Toggling Algorithm](/images/selecting_algorithm.png)

To change the channel, simply double-click on the “Analog Channel” block, select “Import S-Parameter Touchstone File” and click “Browse” to choose a channel from the provided options.

![Selecting Analog Channel](/images/selecting_channel.png)

## Channels

Due to long simulation times, the algorithms were evaluated on 6 representative Medium-Reach (MR) channels from [IEEE P802.3dj Task Force](https://www.ieee802.org/3/dj/public/24_07/lim_3dj_02a_2407.pdf) with insertion losses (ILs) ranging from 24dB to 29dB at 56GHz Nyquist frequency (all under `./Channels/MR` directory):
1. `KRCA_wXTALK_MX_2_PCB-50-50_mm_FO-100-100_mm_CA-200_mm_thru.s4p`
2. `KRCA_wXTALK_MX_3_PCB-75-75_mm_FO-100-100_mm_CA-200_mm_thru.s4p`
3. `KRCA_wXTALK_MX_5_PCB-50-50_mm_FO-200-200_mm_CA-200_mm_thru.s4p`
4. `KRCA_wXTALK_MX_6_PCB-75-75_mm_FO-200-200_mm_CA-200_mm_thru.s4p`
5. `KRCA_wXTALK_MX_10_PCB-25-25_mm_FO-100-100_mm_CA-500_mm_thru.s4p`
6. `KRCA_wXTALK_MX_11_PCB-50-50_mm_FO-100-100_mm_CA-500_mm_thru.s4p`

## Margin Lock – Results

The figure below shows that power savings were achieved across all channels except MX\_10, and the algorithm achieved an average power reduction of 35.8%. In channel MX\_10, the algorithm determined that all taps were required to maintain signal integrity and therefore did not disable any taps. This behaviour demonstrates that the algorithm performs as intended, selectively disabling taps when possible while maintaining signal quality.

![Margin Lock Power Savings](/images/margin_lock_power_savings.png)
