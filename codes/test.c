/*
  Embedded math simulation harness.
  This script uses the exact same signal generation and Monte-Carlo loop
  as the original desktop code, but replaces the core estimation logic
  with the float-precision Newton-Raphson math from the embedded MCU.
*/

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <complex.h>
#include <string.h>
#include <time.h>
#include <fftw3.h>

/* LAPACK for refine_fest (so we can compare fa and fb apples-to-apples) */
extern void dgels_(char *trans, int *m, int *n, int *nrhs,
                   double *a, int *lda,
                   double *b, int *ldb,
                   double *work, int *lwork, int *info);

/* -------------------- Random number helpers -------------------- */
static double urand_0_1(void) {
    return (rand() + 1.0) / (RAND_MAX + 2.0);
}

static double uniform(double a, double b) {
    return a + (b - a) * urand_0_1();
}

static double gauss(double sigma) {
    double u1 = urand_0_1();
    double u2 = urand_0_1();
    double r = sqrt(-2.0 * log(u1));
    double th = 2.0 * M_PI * u2;
    return sigma * r * cos(th);
}

static void gnuplot_load(const char *fn) {
    FILE *pipe = popen("gnuplot -persist", "w");
    if (!pipe) {
        printf("# error: could not open gnuplot pipe\n");
        return;
    }
    fprintf(pipe, "load '%s'\n", fn);
    fflush(pipe);
    pclose(pipe);
}

static int argmax_abs_complex(const double _Complex *x, int len) {
    int idx = 0;
    double best = cabs(x[0]);
    for (int i = 1; i < len; i++) {
        double v = cabs(x[i]);
        if (v > best) {
            best = v;
            idx = i;
        }
    }
    return idx;
}

/* ================= Embedded Math Types ================= */
typedef struct {
    float re;
    float im;
} complex_t;

static inline complex_t cdiv(complex_t a, complex_t b) {
    float denom = b.re*b.re + b.im*b.im;
    complex_t res;
    res.re = (a.re*b.re + a.im*b.im) / denom;
    res.im = (a.im*b.re - a.re*b.im) / denom;
    return res;
}

static inline complex_t cmul(complex_t a, complex_t b) {
    complex_t res;
    res.re = a.re*b.re - a.im*b.im;
    res.im = a.re*b.im + a.im*b.re;
    return res;
}

static inline complex_t cexp_j(float theta) {
    complex_t res;
    res.re = cosf(theta);
    res.im = sinf(theta);
    return res;
}

/* ================= Embedded Polynomial Builder ================= */
void quartic_poly_embedded(
    float N, float fs,
    float fbin[3],
    complex_t dft[3],
    float Q[5]
)
{
    float fr2 = fbin[1];
    complex_t fft1 = dft[0];
    complex_t fft2 = dft[1];
    complex_t fft3 = dft[2];
    
    float k = fr2 * N / fs;
    float pin = 3.1415926535f / N;

    float s = sinf(pin);
    float c = cosf(pin);
    float ssq = s*s;
    float csq = c*c;

    complex_t ratio12 = cdiv(fft1, fft2);
    complex_t ratio32 = cdiv(fft3, fft2);

    float R1 = cmul(ratio12, cexp_j(pin)).re;
    float R3 = cmul(ratio32, cexp_j(-pin)).re;

    float s1 = sinf((2.0f*k - 1.0f)*pin);
    float c1 = cosf((2.0f*k - 1.0f)*pin);
    float s2 = sinf(2.0f*k*pin);
    float c2 = cosf(2.0f*k*pin);
    float s3 = sinf((2.0f*k + 1.0f)*pin);
    float c3 = cosf((2.0f*k + 1.0f)*pin);

    float Up = R1 + R3;
    float Um = R1 - R3;

    float alpha1 = s1 + s3;
    float alpha2 = s1 - s3;
    float beta1  = c1 + c3;
    float beta2  = c1 - c3;

    float phis = s1 * R1 - s3 * R3;
    float phic = c1 * R1 - c3 * R3;

    Q[4] = c * c3 * c1 * Um - csq * c2 * phic + c * c2 * beta2;
    Q[3] = c * (c3 * s1 + c1 * s3) * Um - csq * s2 * phic
         + c1 * c3 * s * Up - csq * c2 * phis
         - c2 * s * beta1 + c * s2 * beta2 + c * c2 * alpha2;
    Q[2] = ssq * c2 * phic - csq * s2 * phis
         + s * (c3 * s1 + s3 * c1) * Up
         + s3 * c * s1 * Um
         + s2 * c * alpha2 - c2 * s * alpha1 - s2 * s * beta1;
    Q[1] = ssq * (s2 * phic + c2 * phis)
         + s * s1 * s3 * Up - s * s2 * alpha1;
    Q[0] = ssq * s2 * phis;
}

/* ================= Embedded Newton-Raphson Solver ================= */
float solve_quartic_newton(float Q[5])
{
    float x = 0.0f; 
    int i;
    for (i = 0; i < 10; i++) {
        float f =
            Q[4]*x*x*x*x +
            Q[3]*x*x*x +
            Q[2]*x*x +
            Q[1]*x +
            Q[0];

        float df =
            4*Q[4]*x*x*x +
            3*Q[3]*x*x +
            2*Q[2]*x +
            Q[1];

        if (fabsf(df) < 1e-6f) break;

        x = x - f/df;
    }
    return x;
}

/* -------------------- Exact DFT for a single frequency -------------------- */
static double _Complex DFT(const double *s, int N, double fs, double f) {
    double w = 2.0 * M_PI * f;
    double _Complex dft = 0.0 + I * 0.0;
    for (int k = 0; k < N; k++) {
        double wt = w * k / fs;
        dft += s[k] * (cos(wt) - I * sin(wt));
    }
    return dft;
}

/* -------------------- refine_fest: LS solve (real) -------------------- */
static double refine_fest(
    const double *t, const double *sign, int N,
    double *aes, double *pes,
    double fes
) {
    double wes = 2.0 * M_PI * fes;
    double fs = 1.0 / (t[1] - t[0]);

    double *A = (double*)malloc(sizeof(double) * N * 2);
    double *B = (double*)malloc(sizeof(double) * N);

    for (int i = 0; i < N; i++) {
        double ang = wes * t[i] + (*pes);
        double C = cos(ang);
        double S = sin(ang);

        B[i] = sign[i] / (*aes) - C;
        A[i + 0*N] = -t[i] * S;
        A[i + 1*N] = -S;
    }

    char trans = 'N';
    int m = N, n = 2, nrhs = 1;
    int lda = N;
    int ldb = (N > 2 ? N : 2);
    int info;

    double *Bwork = (double*)calloc(ldb, sizeof(double));
    for (int i = 0; i < N; i++) Bwork[i] = B[i];

    int lwork = -1;
    double wkopt;

    dgels_(&trans, &m, &n, &nrhs, A, &lda, Bwork, &ldb, &wkopt, &lwork, &info);
    if (info != 0) {
        free(A); free(B); free(Bwork);
        return fes;
    }

    lwork = (int)wkopt;
    double *work = (double*)malloc(sizeof(double) * lwork);
    dgels_(&trans, &m, &n, &nrhs, A, &lda, Bwork, &ldb, work, &lwork, &info);

    double x0 = Bwork[0];
    double x1 = Bwork[1];

    free(A); free(B); free(Bwork); free(work);

    if (info != 0) return fes;

    double fes0 = (x0 + wes) / (2.0 * M_PI);
    if (fes0 > fes + fs / N || fes0 < fes - fs / N) return fes;
    return fes0;
}

/* -------------------- Signal generator -------------------- */
static void cos_signal(double *s, const double *t, int N, double a, double f0, double phi0) {
    for (int i = 0; i < N; i++) {
        s[i] = a * cos(2.0 * M_PI * f0 * t[i] + phi0);
    }
}

/* -------------------- Plot script -------------------- */
static void plot_fig2_embedded(void) {
    FILE *fout = fopen("fgnuplotinskey", "w");
    if (!fout) return;

    fprintf(fout, "reset\n");
    fprintf(fout, "set term wxt\n");
    fprintf(fout, "set grid\n");
    fprintf(fout, "set xlabel 'SNR [dB]'\n");
    fprintf(fout, "set ylabel 'RMSE [dB]'\n");
    fprintf(fout, "set key top right\n");
    fprintf(fout, "set yrange [-60:50]\n");

    fprintf(fout,
        "plot 'quartic_embedded_results' u 1:2 w lp lw 2 t 'CRLB', "
        "'quartic_embedded_results' u 1:3 w lp lw 2 t 'Embedded Float (Newton)', "
        "'quartic_embedded_results' u 1:4 w lp lw 2 t 'Refined FB'\n"
    );

    fclose(fout);
    gnuplot_load("fgnuplotinskey");
}

/* -------------------- MAIN -------------------- */
int main(void) {
    srand((unsigned)time(NULL));

    int N = 128;
    double f0 = 100;
    double fs = 1000.0;
    double Vm = 1.0;

    int snr_len = (int)((50.0 - (-10.0)) / 2.0) + 1;
    double *snrdb = (double*)malloc(sizeof(double) * snr_len);
    for (int i = 0; i < snr_len; i++) snrdb[i] = -10.0 + 2.0 * i;

    double *t = (double*)malloc(sizeof(double) * N);
    for (int i = 0; i < N; i++) t[i] = (double)i / fs;

    double *sig = (double*)malloc(sizeof(double) * N);
    double phi0 = uniform(0.0, 2.0 * M_PI);
    cos_signal(sig, t, N, 1.0, f0, phi0);

    fftw_complex *fftw_in  = (fftw_complex*)fftw_malloc(sizeof(fftw_complex) * N);
    fftw_complex *fftw_out = (fftw_complex*)fftw_malloc(sizeof(fftw_complex) * N);
    fftw_plan plan = fftw_plan_dft_1d(N, fftw_in, fftw_out, FFTW_FORWARD, FFTW_ESTIMATE);

    int nitmax = 10000;

    FILE *fout = fopen("quartic_embedded_results", "w");
    if (!fout) return 1;

    double *sign = (double*)malloc(sizeof(double) * N);
    double _Complex *fftsigs = (double _Complex*)malloc(sizeof(double _Complex) * N);
    double _Complex *halfvec = (double _Complex*)malloc(sizeof(double _Complex) * (N/2));

    for (int i = 0; i < snr_len; i++) {
        double snr = pow(10.0, snrdb[i] / 10.0);
        double crlb = 12.0 / (snr * N * (N * N - 1.0) * pow(2.0 * M_PI, 2.0));
        double noise_sigma = sqrt(0.5 * Vm * Vm / snr);

        double msea = 0.0;
        double mseb = 0.0;

        for (int nit = 0; nit < nitmax; nit++) {
            for (int k = 0; k < N; k++) sign[k] = sig[k] + gauss(noise_sigma);
            for (int k = 0; k < N; k++) fftw_in[k] = sign[k] + I*0.0;
            
            fftw_execute(plan);
            for (int k = 0; k < N; k++) fftsigs[k] = fftw_out[k];

            int half = N / 2;
            for (int k = 0; k < half; k++) halfvec[k] = fftsigs[k] * (2.0 / N);

            int m2 = argmax_abs_complex(halfvec, half);
            int m1 = m2 - 1;
            int m3 = m2 + 1;

            if (m1 < 0) m1 = 0;
            if (m3 >= half) m3 = half - 1;

            /* Embedded Math Translation */
            float fbin_f[3];
            fbin_f[0] = (float)(fs * m1 / N);
            fbin_f[1] = (float)(fs * m2 / N);
            fbin_f[2] = (float)(fs * m3 / N);

            complex_t fftbin_f[3];
            fftbin_f[0].re = (float)creal(fftsigs[m1]); fftbin_f[0].im = (float)cimag(fftsigs[m1]);
            fftbin_f[1].re = (float)creal(fftsigs[m2]); fftbin_f[1].im = (float)cimag(fftsigs[m2]);
            fftbin_f[2].re = (float)creal(fftsigs[m3]); fftbin_f[2].im = (float)cimag(fftsigs[m3]);

            float Q_f[5];
            quartic_poly_embedded((float)N, (float)fs, fbin_f, fftbin_f, Q_f);

            float root = solve_quartic_newton(Q_f);
            float del = 2.0f * atanf(root) * (float)fs; 
            double fa = (double)(fbin_f[1] + (del / (2.0f * 3.1415926535f)));

            /* Desktop refine_fest to see if it still improves things */
            double _Complex peak_dft = DFT(sign, N, fs, fa);
            double aa = 2.0 * cabs(peak_dft) / N;
            double pa = atan2(cimag(peak_dft), creal(peak_dft));
            double fb = refine_fest(t, sign, N, &aa, &pa, fa);

            msea += (fa - f0) * (fa - f0);
            mseb += (fb - f0) * (fb - f0);
        }

        double rmsea = 10.0 * log10(sqrt(msea / nitmax));
        double rmseb = 10.0 * log10(sqrt(mseb / nitmax));
        double rcrlb = 10.0 * log10(sqrt(crlb));

        fprintf(fout, "%.6f  %.6f  %.6f  %.6f\n", snrdb[i], rcrlb, rmsea, rmseb);
        fflush(fout);
        printf("SNR=%.1f dB done\n", snrdb[i]);
    }

    fclose(fout);

    fftw_destroy_plan(plan);
    fftw_free(fftw_in);
    fftw_free(fftw_out);
    free(sign); free(fftsigs); free(halfvec);
    free(snrdb); free(t); free(sig);

    plot_fig2_embedded();

    return 0;
}