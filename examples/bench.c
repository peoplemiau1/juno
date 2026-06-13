#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

void* worker(void* arg) {
    long sum = 0;
    long limit = 100000000;
    for (long i = 0; i < limit; i++) {
        sum = (sum + i) * 3 / 3;
    }
    return (void*)sum;
}

int main() {
    printf("C Multithreading Benchmark Started...\n");
    pthread_t t1, t2, t3, t4;

    pthread_create(&t1, NULL, worker, (void*)1);
    pthread_create(&t2, NULL, worker, (void*)2);
    pthread_create(&t3, NULL, worker, (void*)3);
    pthread_create(&t4, NULL, worker, (void*)4);

    pthread_join(t1, NULL);
    pthread_join(t2, NULL);
    pthread_join(t3, NULL);
    pthread_join(t4, NULL);

    printf("C Benchmark Finished!\n");
    return 0;
}
