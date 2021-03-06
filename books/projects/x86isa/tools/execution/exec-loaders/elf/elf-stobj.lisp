;; ORIGINAL AUTHOR:
;; Soumava Ghosh       <soumava@cs.utexas.edu>

(in-package "X86ISA")

(include-book "elf-constants"
              :ttags (:syscall-exec :include-raw :other-non-det :undef-flg))

(local (include-book "std/lists/nthcdr" :dir :system))

(local (include-book "std/lists/take" :dir :system))

;; ========================================================

;; A stobj to store some useful info during the parsing process

(defconst *elf-body*
  `(
    (elf-file-size                  :type (satisfies natp)   :initially 0)
    (sections-num                   :type (unsigned-byte 64) :initially 0)
    (elf-header-size                :type (unsigned-byte 64) :initially 0)

    ;; note-ABI-tag section
    (note-ABI-tag-addr              :type (unsigned-byte 64)     :initially 0)
    (note-ABI-tag-size              :type (unsigned-byte 64)     :initially 0)
    (note-ABI-tag-offset            :type (unsigned-byte 64)     :initially 0)
    (note-ABI-tag-bytes             :type (satisfies byte-listp) :initially nil)

    ;; note-gnu-build-id section
    (note-gnu-buildid-addr          :type (unsigned-byte 64)     :initially 0)
    (note-gnu-buildid-size          :type (unsigned-byte 64)     :initially 0)
    (note-gnu-buildid-offset        :type (unsigned-byte 64)     :initially 0)
    (note-gnu-buildid-bytes         :type (satisfies byte-listp) :initially nil)

    ;; rela-plt section
    (rela-plt-addr                  :type (unsigned-byte 64)     :initially 0)
    (rela-plt-size                  :type (unsigned-byte 64)     :initially 0)
    (rela-plt-offset                :type (unsigned-byte 64)     :initially 0)
    (rela-plt-bytes                 :type (satisfies byte-listp) :initially nil)

    ;; init section
    (init-addr                      :type (unsigned-byte 64)     :initially 0)
    (init-size                      :type (unsigned-byte 64)     :initially 0)
    (init-offset                    :type (unsigned-byte 64)     :initially 0)
    (init-bytes                     :type (satisfies byte-listp) :initially nil)

    ;; plt section
    (plt-addr                       :type (unsigned-byte 64)     :initially 0)
    (plt-size                       :type (unsigned-byte 64)     :initially 0)
    (plt-offset                     :type (unsigned-byte 64)     :initially 0)
    (plt-bytes                      :type (satisfies byte-listp) :initially nil)

    ;; text section
    (text-addr                      :type (unsigned-byte 64)     :initially 0)
    (text-size                      :type (unsigned-byte 64)     :initially 0)
    (text-offset                    :type (unsigned-byte 64)     :initially 0)
    (text-bytes                     :type (satisfies byte-listp) :initially nil)

    ;; fini section
    (fini-addr                      :type (unsigned-byte 64)     :initially 0)
    (fini-size                      :type (unsigned-byte 64)     :initially 0)
    (fini-offset                    :type (unsigned-byte 64)     :initially 0)
    (fini-bytes                     :type (satisfies byte-listp) :initially nil)

    ;; rodata section
    (rodata-addr                    :type (unsigned-byte 64)     :initially 0)
    (rodata-size                    :type (unsigned-byte 64)     :initially 0)
    (rodata-offset                  :type (unsigned-byte 64)     :initially 0)
    (rodata-bytes                   :type (satisfies byte-listp) :initially nil)

    ;; eh-frame section
    (eh-frame-addr                  :type (unsigned-byte 64)     :initially 0)
    (eh-frame-size                  :type (unsigned-byte 64)     :initially 0)
    (eh-frame-offset                :type (unsigned-byte 64)     :initially 0)
    (eh-frame-bytes                 :type (satisfies byte-listp) :initially nil)

    ;; gcc-except-table section
    (gcc-except-table-addr          :type (unsigned-byte 64)     :initially 0)
    (gcc-except-table-size          :type (unsigned-byte 64)     :initially 0)
    (gcc-except-table-offset        :type (unsigned-byte 64)     :initially 0)
    (gcc-except-table-bytes         :type (satisfies byte-listp) :initially nil)

    ;; init-array section
    (init-array-addr                :type (unsigned-byte 64)     :initially 0)
    (init-array-size                :type (unsigned-byte 64)     :initially 0)
    (init-array-offset              :type (unsigned-byte 64)     :initially 0)
    (init-array-bytes               :type (satisfies byte-listp) :initially nil)

    ;; fini-array section
    (fini-array-addr                :type (unsigned-byte 64)     :initially 0)
    (fini-array-size                :type (unsigned-byte 64)     :initially 0)
    (fini-array-offset              :type (unsigned-byte 64)     :initially 0)
    (fini-array-bytes               :type (satisfies byte-listp) :initially nil)

    ;; ctors section
    (ctors-addr                     :type (unsigned-byte 64)     :initially 0)
    (ctors-size                     :type (unsigned-byte 64)     :initially 0)
    (ctors-offset                   :type (unsigned-byte 64)     :initially 0)
    (ctors-bytes                    :type (satisfies byte-listp) :initially nil)

    ;; dtors section
    (dtors-addr                     :type (unsigned-byte 64)     :initially 0)
    (dtors-size                     :type (unsigned-byte 64)     :initially 0)
    (dtors-offset                   :type (unsigned-byte 64)     :initially 0)
    (dtors-bytes                    :type (satisfies byte-listp) :initially nil)

    ;; jcr section
    (jcr-addr                       :type (unsigned-byte 64)     :initially 0)
    (jcr-size                       :type (unsigned-byte 64)     :initially 0)
    (jcr-offset                     :type (unsigned-byte 64)     :initially 0)
    (jcr-bytes                      :type (satisfies byte-listp) :initially nil)

    ;; data-rel-ro section
    (data-rel-ro-addr               :type (unsigned-byte 64)     :initially 0)
    (data-rel-ro-size               :type (unsigned-byte 64)     :initially 0)
    (data-rel-ro-offset             :type (unsigned-byte 64)     :initially 0)
    (data-rel-ro-bytes              :type (satisfies byte-listp) :initially nil)

    ;; got section
    (got-addr                       :type (unsigned-byte 64)     :initially 0)
    (got-size                       :type (unsigned-byte 64)     :initially 0)
    (got-offset                     :type (unsigned-byte 64)     :initially 0)
    (got-bytes                      :type (satisfies byte-listp) :initially nil)

    ;; got-plt section
    (got-plt-addr                   :type (unsigned-byte 64)     :initially 0)
    (got-plt-size                   :type (unsigned-byte 64)     :initially 0)
    (got-plt-offset                 :type (unsigned-byte 64)     :initially 0)
    (got-plt-bytes                  :type (satisfies byte-listp) :initially nil)

    ;; data section
    (data-addr                      :type (unsigned-byte 64)     :initially 0)
    (data-size                      :type (unsigned-byte 64)     :initially 0)
    (data-offset                    :type (unsigned-byte 64)     :initially 0)
    (data-bytes                     :type (satisfies byte-listp) :initially nil)

    ;; tdata section
    (tdata-addr                     :type (unsigned-byte 64)     :initially 0)
    (tdata-size                     :type (unsigned-byte 64)     :initially 0)
    (tdata-offset                   :type (unsigned-byte 64)     :initially 0)
    (tdata-bytes                    :type (satisfies byte-listp) :initially nil)

    ;; bss section
    (bss-addr                       :type (unsigned-byte 64)     :initially 0)
    (bss-size                       :type (unsigned-byte 64)     :initially 0)
    (bss-offset                     :type (unsigned-byte 64)     :initially 0)
    (bss-bytes                      :type (satisfies byte-listp) :initially nil)

    ;; tbss section
    (tbss-addr                      :type (unsigned-byte 64)     :initially 0)
    (tbss-size                      :type (unsigned-byte 64)     :initially 0)
    (tbss-offset                    :type (unsigned-byte 64)     :initially 0)
    (tbss-bytes                     :type (satisfies byte-listp) :initially nil)

    ))

(defun create-elf-stobj-1 (elf)
  `(DEFSTOBJ ELF
     ,@elf
     :INLINE t
     :RENAMING (,@(create-stobj-renaming-fn elf))))

(defmacro create-elf-stobj ()
  (create-elf-stobj-1 *elf-body*))

(create-elf-stobj)

;; ===================================================================
