#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default")))
#endif

#if defined(MYREAL4)
typedef float my_real;
#else
typedef double my_real;
#endif

#if defined(_MSC_VER)
#define THREAD_LOCAL __declspec(thread)
#elif defined(__GNUC__) || defined(__clang__)
#define THREAD_LOCAL __thread
#else
#define THREAD_LOCAL
#endif

#define UNUSED(x) (void)(x)
#define USERLIB_VERSION 1300000000

static THREAD_LOCAL my_real *g_so[6];
static THREAD_LOCAL my_real *g_de[6];
static THREAD_LOCAL my_real *g_rho0;

static THREAD_LOCAL my_real *g_shell_so[5];
static THREAD_LOCAL my_real *g_shell_thkn;

static THREAD_LOCAL my_real *solid_s[6];
static THREAD_LOCAL my_real *solid_sv[6];
static THREAD_LOCAL my_real *solid_dpla;
static THREAD_LOCAL int solid_capacity;
static THREAD_LOCAL int solid_n;

static THREAD_LOCAL my_real *shell_s[5];
static THREAD_LOCAL my_real *shell_sv[5];
static THREAD_LOCAL my_real *shell_dpla;
static THREAD_LOCAL my_real *shell_etse;
static THREAD_LOCAL my_real *shell_thkn;
static THREAD_LOCAL int shell_capacity;
static THREAD_LOCAL int shell_n;

static int grow_array(my_real **array, int n)
{
    my_real *tmp = (my_real *)realloc(*array, (size_t)n * sizeof(my_real));

    if (!tmp) {
        return 0;
    }

    *array = tmp;
    return 1;
}

static int ensure_solid_capacity(int n)
{
    int i;

    if (n <= solid_capacity) {
        return 1;
    }

    for (i = 0; i < 6; ++i) {
        if (!grow_array(&solid_s[i], n) || !grow_array(&solid_sv[i], n)) {
            return 0;
        }
    }
    if (!grow_array(&solid_dpla, n)) {
        return 0;
    }

    solid_capacity = n;
    return 1;
}

static int ensure_shell_capacity(int n)
{
    int i;

    if (n <= shell_capacity) {
        return 1;
    }

    for (i = 0; i < 5; ++i) {
        if (!grow_array(&shell_s[i], n) || !grow_array(&shell_sv[i], n)) {
            return 0;
        }
    }
    if (!grow_array(&shell_dpla, n) || !grow_array(&shell_etse, n) || !grow_array(&shell_thkn, n)) {
        return 0;
    }

    shell_capacity = n;
    return 1;
}

static void copy_fortran_string(char *dst, size_t dst_size, const char *src, int len)
{
    int i;
    int n;

    if (!dst || dst_size == 0) {
        return;
    }

    dst[0] = '\0';
    if (!src || len <= 0) {
        return;
    }

    n = len;
    if ((size_t)n >= dst_size) {
        n = (int)dst_size - 1;
    }

    for (i = 0; i < n; ++i) {
        dst[i] = src[i];
    }
    dst[n] = '\0';

    while (n > 0 && isspace((unsigned char)dst[n - 1])) {
        dst[n - 1] = '\0';
        --n;
    }
}

static int parse_j2_parameters(const char *root, int ilaw, double *E, double *nu, double *Y0, double *H)
{
    char filename[1024];
    char line[1024];
    FILE *fp;

    snprintf(filename, sizeof(filename), "SI%s_%04d.scr", root ? root : "", ilaw);
    fp = fopen(filename, "r");
    if (!fp) {
        return 0;
    }

    while (fgets(line, sizeof(line), fp)) {
        char *p = line;
        while (*p && isspace((unsigned char)*p)) {
            ++p;
        }
        if (*p == '\0' || *p == '#' || *p == '/' || *p == '$') {
            continue;
        }
        if (sscanf(p, "%lf %lf %lf %lf", E, nu, Y0, H) == 4) {
            fclose(fp);
            return 1;
        }
    }

    fclose(fp);
    return 0;
}

static void write_starter_echo(const char *root, int ilaw, double E, double nu, double Y0, double H)
{
    char filename[1024];
    FILE *fp;

    snprintf(filename, sizeof(filename), "SO%s_%04d.scr", root ? root : "", ilaw);
    fp = fopen(filename, "w");
    if (!fp) {
        return;
    }

    fprintf(fp, "\n");
    fprintf(fp, "    USER MATERIAL LAW99.%02d: J2 small-strain isotropic hardening\n", ilaw == 99 ? 1 : ilaw);
    fprintf(fp, "    E      = %.12g\n", E);
    fprintf(fp, "    nu     = %.12g\n", nu);
    fprintf(fp, "    Y0     = %.12g\n", Y0);
    fprintf(fp, "    H      = %.12g\n", H);
    fprintf(fp, "    UVAR(1)= equivalent plastic strain\n");
    fclose(fp);
}

static void set_default_j2(double *E, double *nu, double *Y0, double *H)
{
    *E = 210000.0;
    *nu = 0.30;
    *Y0 = 250.0;
    *H = 1000.0;
}

static void fill_starter_material(double E, double nu, double Y0, double H,
                                  my_real *uparam, int maxuparam, int *nuparam,
                                  int *nuvar, int *ifunc, int maxfunc, int *nfunc,
                                  my_real *parmat)
{
    double K;
    int i;

    if (nu <= -0.999 || nu >= 0.499 || E <= 0.0) {
        set_default_j2(&E, &nu, &Y0, &H);
    }

    K = E / (3.0 * (1.0 - 2.0 * nu));

    if (nuparam) {
        *nuparam = 4;
    }
    if (nuvar) {
        *nuvar = 1;
    }
    if (nfunc) {
        *nfunc = 0;
    }

    if (ifunc && maxfunc > 0) {
        for (i = 0; i < maxfunc; ++i) {
            ifunc[i] = 0;
        }
    }

    if (uparam && maxuparam > 0) {
        if (maxuparam > 0) {
            uparam[0] = (my_real)E;
        }
        if (maxuparam > 1) {
            uparam[1] = (my_real)nu;
        }
        if (maxuparam > 2) {
            uparam[2] = (my_real)Y0;
        }
        if (maxuparam > 3) {
            uparam[3] = (my_real)H;
        }
    }

    if (parmat) {
        for (i = 0; i < 100; ++i) {
            parmat[i] = (my_real)0;
        }
        parmat[0] = (my_real)K;
        parmat[1] = (my_real)E;
        parmat[2] = (my_real)nu;
        parmat[15] = (my_real)0;
        parmat[16] = (my_real)0;
    }
}

EXPORT void userlib_id(int *info)
{
    if (info) {
        *info = USERLIB_VERSION;
    }
}

EXPORT void set_callback(void *callback_array[200])
{
    UNUSED(callback_array);
}

EXPORT void st_lecm99_(int *ilaw, char *rootn, int *rootlen, int *iuser_law,
                       my_real *uparam, int *maxuparam, int *nuparam, int *nuvar,
                       int *ifunc, int *maxfunc, int *nfunc, my_real *parmat)
{
    char root[512];
    double E, nu, Y0, H;
    int law = ilaw ? *ilaw : 99;
    int maxu = maxuparam ? *maxuparam : 0;
    int maxf = maxfunc ? *maxfunc : 0;

    UNUSED(iuser_law);
    set_default_j2(&E, &nu, &Y0, &H);
    copy_fortran_string(root, sizeof(root), rootn, rootlen ? *rootlen : 0);
    if (!parse_j2_parameters(root, law, &E, &nu, &Y0, &H)) {
        fprintf(stderr, "raduser_j2_law99: using default J2 parameters; scratch file was not readable\n");
    }

    write_starter_echo(root, law, E, nu, Y0, H);
    fill_starter_material(E, nu, Y0, H, uparam, maxu, nuparam, nuvar, ifunc, maxf, nfunc, parmat);
}

EXPORT void ST_LECM99(int *ilaw, char *rootn, int *rootlen, int *iuser_law,
                      my_real *uparam, int *maxuparam, int *nuparam, int *nuvar,
                      int *ifunc, int *maxfunc, int *nfunc, my_real *parmat)
{
    st_lecm99_(ilaw, rootn, rootlen, iuser_law, uparam, maxuparam, nuparam, nuvar,
               ifunc, maxfunc, nfunc, parmat);
}

EXPORT void st_get_userbuf_var_(int *id, char *title)
{
    UNUSED(id);
    UNUSED(title);
}

EXPORT void ST_GET_USERBUF_VAR(int *id, char *title)
{
    st_get_userbuf_var_(id, title);
}

EXPORT void eng_get_law_user_var_(int *NCYCLE, int *IMAT, int *IPTR, int *IPTS, int *IPTT,
                                  my_real *R11, my_real *R12, my_real *R13,
                                  my_real *R21, my_real *R22, my_real *R23,
                                  my_real *R31, my_real *R32, my_real *R33,
                                  my_real *SO1, my_real *SO2, my_real *SO3,
                                  my_real *SO4, my_real *SO5, my_real *SO6,
                                  my_real *EP1, my_real *EP2, my_real *EP3,
                                  my_real *EP4, my_real *EP5, my_real *EP6,
                                  my_real *ES1, my_real *ES2, my_real *ES3,
                                  my_real *ES4, my_real *ES5, my_real *ES6,
                                  my_real *DE1, my_real *DE2, my_real *DE3,
                                  my_real *DE4, my_real *DE5, my_real *DE6,
                                  my_real *RHO0,
                                  my_real *S1, my_real *S2, my_real *S3,
                                  my_real *S4, my_real *S5, my_real *S6,
                                  my_real *SV1, my_real *SV2, my_real *SV3,
                                  my_real *SV4, my_real *SV5, my_real *SV6)
{
    UNUSED(NCYCLE);
    UNUSED(IMAT);
    UNUSED(IPTR);
    UNUSED(IPTS);
    UNUSED(IPTT);
    UNUSED(R11);
    UNUSED(R12);
    UNUSED(R13);
    UNUSED(R21);
    UNUSED(R22);
    UNUSED(R23);
    UNUSED(R31);
    UNUSED(R32);
    UNUSED(R33);
    UNUSED(EP1);
    UNUSED(EP2);
    UNUSED(EP3);
    UNUSED(EP4);
    UNUSED(EP5);
    UNUSED(EP6);
    UNUSED(ES1);
    UNUSED(ES2);
    UNUSED(ES3);
    UNUSED(ES4);
    UNUSED(ES5);
    UNUSED(ES6);
    UNUSED(S1);
    UNUSED(S2);
    UNUSED(S3);
    UNUSED(S4);
    UNUSED(S5);
    UNUSED(S6);
    UNUSED(SV1);
    UNUSED(SV2);
    UNUSED(SV3);
    UNUSED(SV4);
    UNUSED(SV5);
    UNUSED(SV6);

    g_so[0] = SO1;
    g_so[1] = SO2;
    g_so[2] = SO3;
    g_so[3] = SO4;
    g_so[4] = SO5;
    g_so[5] = SO6;

    g_de[0] = DE1;
    g_de[1] = DE2;
    g_de[2] = DE3;
    g_de[3] = DE4;
    g_de[4] = DE5;
    g_de[5] = DE6;

    g_rho0 = RHO0;
}

EXPORT void ENG_GET_LAW_USER_VAR(int *NCYCLE, int *IMAT, int *IPTR, int *IPTS, int *IPTT,
                                 my_real *R11, my_real *R12, my_real *R13,
                                 my_real *R21, my_real *R22, my_real *R23,
                                 my_real *R31, my_real *R32, my_real *R33,
                                 my_real *SO1, my_real *SO2, my_real *SO3,
                                 my_real *SO4, my_real *SO5, my_real *SO6,
                                 my_real *EP1, my_real *EP2, my_real *EP3,
                                 my_real *EP4, my_real *EP5, my_real *EP6,
                                 my_real *ES1, my_real *ES2, my_real *ES3,
                                 my_real *ES4, my_real *ES5, my_real *ES6,
                                 my_real *DE1, my_real *DE2, my_real *DE3,
                                 my_real *DE4, my_real *DE5, my_real *DE6,
                                 my_real *RHO0,
                                 my_real *S1, my_real *S2, my_real *S3,
                                 my_real *S4, my_real *S5, my_real *S6,
                                 my_real *SV1, my_real *SV2, my_real *SV3,
                                 my_real *SV4, my_real *SV5, my_real *SV6)
{
    eng_get_law_user_var_(NCYCLE, IMAT, IPTR, IPTS, IPTT,
                          R11, R12, R13, R21, R22, R23, R31, R32, R33,
                          SO1, SO2, SO3, SO4, SO5, SO6,
                          EP1, EP2, EP3, EP4, EP5, EP6,
                          ES1, ES2, ES3, ES4, ES5, ES6,
                          DE1, DE2, DE3, DE4, DE5, DE6, RHO0,
                          S1, S2, S3, S4, S5, S6, SV1, SV2, SV3, SV4, SV5, SV6);
}

EXPORT void eng_sigeps99_(int *NEL, int *NUPARAM, int *NUVAR, int *ILAW_USER, int *NFUNC,
                          int *IFUNC, int *NPF, my_real *TF, my_real *TIME, my_real *TIMESTEP,
                          my_real *UPARAM, my_real *RHO, my_real *VOLUME, my_real *EINT,
                          int *NGL, my_real *SOUNDSP, my_real *VISCMAX, my_real *UVAR,
                          my_real *OFF, my_real *SIGY, my_real *PLA)
{
    int n = NEL && *NEL > 0 ? *NEL : 0;
    int i;
    double E = UPARAM ? (double)UPARAM[0] : 210000.0;
    double nu = UPARAM ? (double)UPARAM[1] : 0.30;
    double Y0 = UPARAM ? (double)UPARAM[2] : 250.0;
    double H = UPARAM ? (double)UPARAM[3] : 1000.0;
    double G;
    double K;
    const double tiny = 1.0e-20;

    UNUSED(NUPARAM);
    UNUSED(ILAW_USER);
    UNUSED(NFUNC);
    UNUSED(IFUNC);
    UNUSED(NPF);
    UNUSED(TF);
    UNUSED(TIME);
    UNUSED(TIMESTEP);
    UNUSED(VOLUME);
    UNUSED(NGL);
    UNUSED(g_rho0);

    solid_n = 0;
    if (n <= 0 || !ensure_solid_capacity(n)) {
        return;
    }
    solid_n = n;

    if (nu <= -0.999 || nu >= 0.499 || E <= 0.0) {
        set_default_j2(&E, &nu, &Y0, &H);
    }

    G = E / (2.0 * (1.0 + nu));
    K = E / (3.0 * (1.0 - 2.0 * nu));

    for (i = 0; i < n; ++i) {
        double old_sig[6];
        double deps[6];
        double p_old;
        double dev_trial[6];
        double p_trial;
        double trace_deps;
        double seq_trial;
        double epbar_old;
        double epbar_new;
        double fy;
        double dgamma = 0.0;
        double scale = 1.0;
        double sig_new[6];
        double work;
        int k;

        for (k = 0; k < 6; ++k) {
            old_sig[k] = g_so[k] ? (double)g_so[k][i] : 0.0;
            deps[k] = g_de[k] ? (double)g_de[k][i] : 0.0;
            solid_sv[k][i] = (my_real)0;
        }

        if (OFF && OFF[i] <= (my_real)0) {
            for (k = 0; k < 6; ++k) {
                solid_s[k][i] = (my_real)old_sig[k];
            }
            solid_dpla[i] = (my_real)0;
            continue;
        }

        p_old = (old_sig[0] + old_sig[1] + old_sig[2]) / 3.0;
        trace_deps = deps[0] + deps[1] + deps[2];
        p_trial = p_old + K * trace_deps;

        dev_trial[0] = old_sig[0] - p_old + 2.0 * G * (deps[0] - trace_deps / 3.0);
        dev_trial[1] = old_sig[1] - p_old + 2.0 * G * (deps[1] - trace_deps / 3.0);
        dev_trial[2] = old_sig[2] - p_old + 2.0 * G * (deps[2] - trace_deps / 3.0);
        dev_trial[3] = old_sig[3] + G * deps[3];
        dev_trial[4] = old_sig[4] + G * deps[4];
        dev_trial[5] = old_sig[5] + G * deps[5];

        seq_trial = sqrt(1.5 * (dev_trial[0] * dev_trial[0] +
                                dev_trial[1] * dev_trial[1] +
                                dev_trial[2] * dev_trial[2] +
                                2.0 * (dev_trial[3] * dev_trial[3] +
                                       dev_trial[4] * dev_trial[4] +
                                       dev_trial[5] * dev_trial[5])));

        epbar_old = (UVAR && (!NUVAR || *NUVAR >= 1)) ? (double)UVAR[i] : 0.0;
        epbar_new = epbar_old;
        fy = Y0 + H * epbar_old;

        if (seq_trial > tiny && seq_trial > fy) {
            dgamma = (seq_trial - fy) / (3.0 * G + H);
            if (dgamma < 0.0) {
                dgamma = 0.0;
            }
            epbar_new = epbar_old + dgamma;
            scale = 1.0 - (3.0 * G * dgamma) / seq_trial;
            if (scale < 0.0) {
                scale = 0.0;
            }
        }

        sig_new[0] = p_trial + scale * dev_trial[0];
        sig_new[1] = p_trial + scale * dev_trial[1];
        sig_new[2] = p_trial + scale * dev_trial[2];
        sig_new[3] = scale * dev_trial[3];
        sig_new[4] = scale * dev_trial[4];
        sig_new[5] = scale * dev_trial[5];

        for (k = 0; k < 6; ++k) {
            solid_s[k][i] = (my_real)sig_new[k];
        }
        solid_dpla[i] = (my_real)dgamma;

        if (UVAR && (!NUVAR || *NUVAR >= 1)) {
            UVAR[i] = (my_real)epbar_new;
        }
        if (PLA) {
            PLA[i] = (my_real)epbar_new;
        }
        if (SIGY) {
            SIGY[i] = (my_real)(Y0 + H * epbar_new);
        }
        if (SOUNDSP && RHO && RHO[i] > (my_real)0) {
            SOUNDSP[i] = (my_real)sqrt((K + 4.0 * G / 3.0) / (double)RHO[i]);
        }
        if (VISCMAX) {
            VISCMAX[i] = (my_real)0;
        }
        if (EINT && RHO && RHO[i] > (my_real)0) {
            work = 0.5 * ((old_sig[0] + sig_new[0]) * deps[0] +
                          (old_sig[1] + sig_new[1]) * deps[1] +
                          (old_sig[2] + sig_new[2]) * deps[2] +
                          (old_sig[3] + sig_new[3]) * deps[3] +
                          (old_sig[4] + sig_new[4]) * deps[4] +
                          (old_sig[5] + sig_new[5]) * deps[5]);
            EINT[i] = (my_real)((double)EINT[i] + work / (double)RHO[i]);
        }
    }
}

EXPORT void ENG_SIGEPS99(int *NEL, int *NUPARAM, int *NUVAR, int *ILAW_USER, int *NFUNC,
                         int *IFUNC, int *NPF, my_real *TF, my_real *TIME, my_real *TIMESTEP,
                         my_real *UPARAM, my_real *RHO, my_real *VOLUME, my_real *EINT,
                         int *NGL, my_real *SOUNDSP, my_real *VISCMAX, my_real *UVAR,
                         my_real *OFF, my_real *SIGY, my_real *PLA)
{
    eng_sigeps99_(NEL, NUPARAM, NUVAR, ILAW_USER, NFUNC, IFUNC, NPF, TF, TIME, TIMESTEP,
                  UPARAM, RHO, VOLUME, EINT, NGL, SOUNDSP, VISCMAX, UVAR, OFF, SIGY, PLA);
}

EXPORT void eng_set_law_user_var_(my_real *S1, my_real *S2, my_real *S3,
                                  my_real *S4, my_real *S5, my_real *S6,
                                  my_real *SV1, my_real *SV2, my_real *SV3,
                                  my_real *SV4, my_real *SV5, my_real *SV6,
                                  my_real *DPLA)
{
    my_real *S[6];
    my_real *SV[6];
    int i;
    int k;

    S[0] = S1;
    S[1] = S2;
    S[2] = S3;
    S[3] = S4;
    S[4] = S5;
    S[5] = S6;
    SV[0] = SV1;
    SV[1] = SV2;
    SV[2] = SV3;
    SV[3] = SV4;
    SV[4] = SV5;
    SV[5] = SV6;

    for (i = 0; i < solid_n; ++i) {
        for (k = 0; k < 6; ++k) {
            if (S[k]) {
                S[k][i] = solid_s[k][i];
            }
            if (SV[k]) {
                SV[k][i] = solid_sv[k][i];
            }
        }
        if (DPLA) {
            DPLA[i] = solid_dpla[i];
        }
    }
}

EXPORT void ENG_SET_LAW_USER_VAR(my_real *S1, my_real *S2, my_real *S3,
                                 my_real *S4, my_real *S5, my_real *S6,
                                 my_real *SV1, my_real *SV2, my_real *SV3,
                                 my_real *SV4, my_real *SV5, my_real *SV6,
                                 my_real *DPLA)
{
    eng_set_law_user_var_(S1, S2, S3, S4, S5, S6, SV1, SV2, SV3, SV4, SV5, SV6, DPLA);
}

EXPORT void eng_get_lawc_user_var_(int *NCYCLE, int *IMAT, int *ILAYER, int *NPTA, int *IFLAG,
                                   my_real *R11, my_real *R12, my_real *R13,
                                   my_real *R21, my_real *R22, my_real *R23,
                                   my_real *R31, my_real *R32, my_real *R33,
                                   my_real *SIGOXX, my_real *SIGOYY, my_real *SIGOXY,
                                   my_real *SIGOYZ, my_real *SIGOZX,
                                   my_real *EPSPXX, my_real *EPSPYY, my_real *EPSPXY,
                                   my_real *EPSPYZ, my_real *EPSPZX,
                                   my_real *EPSXX, my_real *EPSYY, my_real *EPSXY,
                                   my_real *EPSYZ, my_real *EPSZX,
                                   my_real *DEPSXX, my_real *DEPSYY, my_real *DEPSXY,
                                   my_real *DEPSYZ, my_real *DEPSZX,
                                   my_real *THKLYL, my_real *THKN,
                                   my_real *SIGNXX, my_real *SIGNYY, my_real *SIGNXY,
                                   my_real *SIGNYZ, my_real *SIGNZX,
                                   my_real *SIGVXX, my_real *SIGVYY, my_real *SIGVXY,
                                   my_real *SIGVYZ, my_real *SIGVZX, my_real *DPLA)
{
    UNUSED(NCYCLE);
    UNUSED(IMAT);
    UNUSED(ILAYER);
    UNUSED(NPTA);
    UNUSED(IFLAG);
    UNUSED(R11);
    UNUSED(R12);
    UNUSED(R13);
    UNUSED(R21);
    UNUSED(R22);
    UNUSED(R23);
    UNUSED(R31);
    UNUSED(R32);
    UNUSED(R33);
    UNUSED(EPSPXX);
    UNUSED(EPSPYY);
    UNUSED(EPSPXY);
    UNUSED(EPSPYZ);
    UNUSED(EPSPZX);
    UNUSED(EPSXX);
    UNUSED(EPSYY);
    UNUSED(EPSXY);
    UNUSED(EPSYZ);
    UNUSED(EPSZX);
    UNUSED(DEPSXX);
    UNUSED(DEPSYY);
    UNUSED(DEPSXY);
    UNUSED(DEPSYZ);
    UNUSED(DEPSZX);
    UNUSED(THKLYL);
    UNUSED(SIGNXX);
    UNUSED(SIGNYY);
    UNUSED(SIGNXY);
    UNUSED(SIGNYZ);
    UNUSED(SIGNZX);
    UNUSED(SIGVXX);
    UNUSED(SIGVYY);
    UNUSED(SIGVXY);
    UNUSED(SIGVYZ);
    UNUSED(SIGVZX);
    UNUSED(DPLA);

    g_shell_so[0] = SIGOXX;
    g_shell_so[1] = SIGOYY;
    g_shell_so[2] = SIGOXY;
    g_shell_so[3] = SIGOYZ;
    g_shell_so[4] = SIGOZX;
    g_shell_thkn = THKN;
}

EXPORT void ENG_GET_LAWC_USER_VAR(int *NCYCLE, int *IMAT, int *ILAYER, int *NPTA, int *IFLAG,
                                  my_real *R11, my_real *R12, my_real *R13,
                                  my_real *R21, my_real *R22, my_real *R23,
                                  my_real *R31, my_real *R32, my_real *R33,
                                  my_real *SIGOXX, my_real *SIGOYY, my_real *SIGOXY,
                                  my_real *SIGOYZ, my_real *SIGOZX,
                                  my_real *EPSPXX, my_real *EPSPYY, my_real *EPSPXY,
                                  my_real *EPSPYZ, my_real *EPSPZX,
                                  my_real *EPSXX, my_real *EPSYY, my_real *EPSXY,
                                  my_real *EPSYZ, my_real *EPSZX,
                                  my_real *DEPSXX, my_real *DEPSYY, my_real *DEPSXY,
                                  my_real *DEPSYZ, my_real *DEPSZX,
                                  my_real *THKLYL, my_real *THKN,
                                  my_real *SIGNXX, my_real *SIGNYY, my_real *SIGNXY,
                                  my_real *SIGNYZ, my_real *SIGNZX,
                                  my_real *SIGVXX, my_real *SIGVYY, my_real *SIGVXY,
                                  my_real *SIGVYZ, my_real *SIGVZX, my_real *DPLA)
{
    eng_get_lawc_user_var_(NCYCLE, IMAT, ILAYER, NPTA, IFLAG,
                           R11, R12, R13, R21, R22, R23, R31, R32, R33,
                           SIGOXX, SIGOYY, SIGOXY, SIGOYZ, SIGOZX,
                           EPSPXX, EPSPYY, EPSPXY, EPSPYZ, EPSPZX,
                           EPSXX, EPSYY, EPSXY, EPSYZ, EPSZX,
                           DEPSXX, DEPSYY, DEPSXY, DEPSYZ, DEPSZX,
                           THKLYL, THKN, SIGNXX, SIGNYY, SIGNXY, SIGNYZ, SIGNZX,
                           SIGVXX, SIGVYY, SIGVXY, SIGVYZ, SIGVZX, DPLA);
}

EXPORT void eng_sigeps99c_(int *NEL, int *NUPARAM, int *NUVAR, int *ILAW_USER, int *NFUNC,
                           int *IFUNC, int *NPF, int *NGL, my_real *TF, my_real *TIME,
                           my_real *TIMESTEP, my_real *UPARAM, my_real *RHO, my_real *AREA,
                           my_real *EINT, my_real *SHF, my_real *SOUNDSP, my_real *VISCMAX,
                           my_real *PLA, my_real *UVAR, my_real *OFF, my_real *SIGY)
{
    int n = NEL && *NEL > 0 ? *NEL : 0;
    int i;
    int k;

    UNUSED(NUPARAM);
    UNUSED(NUVAR);
    UNUSED(ILAW_USER);
    UNUSED(NFUNC);
    UNUSED(IFUNC);
    UNUSED(NPF);
    UNUSED(NGL);
    UNUSED(TF);
    UNUSED(TIME);
    UNUSED(TIMESTEP);
    UNUSED(UPARAM);
    UNUSED(RHO);
    UNUSED(AREA);
    UNUSED(EINT);
    UNUSED(SHF);
    UNUSED(SOUNDSP);
    UNUSED(VISCMAX);
    UNUSED(PLA);
    UNUSED(UVAR);
    UNUSED(OFF);
    UNUSED(SIGY);

    shell_n = 0;
    if (n <= 0 || !ensure_shell_capacity(n)) {
        return;
    }
    shell_n = n;

    for (i = 0; i < n; ++i) {
        for (k = 0; k < 5; ++k) {
            shell_s[k][i] = g_shell_so[k] ? g_shell_so[k][i] : (my_real)0;
            shell_sv[k][i] = (my_real)0;
        }
        shell_dpla[i] = (my_real)0;
        shell_etse[i] = (my_real)0;
        shell_thkn[i] = g_shell_thkn ? g_shell_thkn[i] : (my_real)0;
    }
}

EXPORT void ENG_SIGEPS99C(int *NEL, int *NUPARAM, int *NUVAR, int *ILAW_USER, int *NFUNC,
                          int *IFUNC, int *NPF, int *NGL, my_real *TF, my_real *TIME,
                          my_real *TIMESTEP, my_real *UPARAM, my_real *RHO, my_real *AREA,
                          my_real *EINT, my_real *SHF, my_real *SOUNDSP, my_real *VISCMAX,
                          my_real *PLA, my_real *UVAR, my_real *OFF, my_real *SIGY)
{
    eng_sigeps99c_(NEL, NUPARAM, NUVAR, ILAW_USER, NFUNC, IFUNC, NPF, NGL, TF, TIME,
                   TIMESTEP, UPARAM, RHO, AREA, EINT, SHF, SOUNDSP, VISCMAX, PLA, UVAR, OFF, SIGY);
}

EXPORT void eng_set_lawc_user_var_(my_real *SIGNXX, my_real *SIGNYY, my_real *SIGNXY,
                                   my_real *SIGNYZ, my_real *SIGNZX,
                                   my_real *SIGVXX, my_real *SIGVYY, my_real *SIGVXY,
                                   my_real *SIGVYZ, my_real *SIGVZX,
                                   my_real *DPLA, my_real *ETSE, my_real *THKN)
{
    my_real *S[5];
    my_real *SV[5];
    int i;
    int k;

    S[0] = SIGNXX;
    S[1] = SIGNYY;
    S[2] = SIGNXY;
    S[3] = SIGNYZ;
    S[4] = SIGNZX;
    SV[0] = SIGVXX;
    SV[1] = SIGVYY;
    SV[2] = SIGVXY;
    SV[3] = SIGVYZ;
    SV[4] = SIGVZX;

    for (i = 0; i < shell_n; ++i) {
        for (k = 0; k < 5; ++k) {
            if (S[k]) {
                S[k][i] = shell_s[k][i];
            }
            if (SV[k]) {
                SV[k][i] = shell_sv[k][i];
            }
        }
        if (DPLA) {
            DPLA[i] = shell_dpla[i];
        }
        if (ETSE) {
            ETSE[i] = shell_etse[i];
        }
        if (THKN) {
            THKN[i] = shell_thkn[i];
        }
    }
}

EXPORT void ENG_SET_LAWC_USER_VAR(my_real *SIGNXX, my_real *SIGNYY, my_real *SIGNXY,
                                  my_real *SIGNYZ, my_real *SIGNZX,
                                  my_real *SIGVXX, my_real *SIGVYY, my_real *SIGVXY,
                                  my_real *SIGVYZ, my_real *SIGVZX,
                                  my_real *DPLA, my_real *ETSE, my_real *THKN)
{
    eng_set_lawc_user_var_(SIGNXX, SIGNYY, SIGNXY, SIGNYZ, SIGNZX,
                           SIGVXX, SIGVYY, SIGVXY, SIGVYZ, SIGVZX, DPLA, ETSE, THKN);
}

EXPORT void st_lecg_(void) {}
EXPORT void st_lecguser_(void) {}
EXPORT void st_lecm_(void) {}
EXPORT void st_lecr_(void) {}
EXPORT void st_lecsen_(void) {}
EXPORT void st_riniuser_(void) {}
EXPORT void st_siniusr_(void) {}
EXPORT void st_userwis_(void) {}
EXPORT void st_userwis_ini_(void) {}

EXPORT void eng_ruser_(void) {}
EXPORT void eng_sigeps_(void) {}
EXPORT void eng_sigepsc_(void) {}
EXPORT void eng_flaw_(void) {}
EXPORT void eng_flawc_(void) {}
EXPORT void eng_suser_(void) {}
EXPORT void eng_userint_(void) {}
EXPORT void eng_get_uintbuf_var_(void) {}
EXPORT void eng_userwi_(void) {}
EXPORT void eng_user_sens_(void) {}

EXPORT void ST_LECG(void) {}
EXPORT void ST_LECGUSER(void) {}
EXPORT void ST_LECM(void) {}
EXPORT void ST_LECR(void) {}
EXPORT void ST_LECSEN(void) {}
EXPORT void ST_RINIUSER(void) {}
EXPORT void ST_SINIUSR(void) {}
EXPORT void ST_USERWIS(void) {}
EXPORT void ST_USERWIS_INI(void) {}

EXPORT void ENG_RUSER(void) {}
EXPORT void ENG_SIGEPS(void) {}
EXPORT void ENG_SIGEPSC(void) {}
EXPORT void ENG_FLAW(void) {}
EXPORT void ENG_FLAWC(void) {}
EXPORT void ENG_SUSER(void) {}
EXPORT void ENG_USERINT(void) {}
EXPORT void ENG_GET_UINTBUF_VAR(void) {}
EXPORT void ENG_USERWI(void) {}
EXPORT void ENG_USER_SENS(void) {}
